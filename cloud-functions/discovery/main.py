"""
Qualys Discovery Cloud Function
Discovers VM instances across target projects and triggers scanning workflows
"""

import base64
import json
import logging
import os
from datetime import datetime, timedelta
from typing import Dict, List, Any

from google.cloud import compute_v1
from google.cloud import firestore
from google.cloud import workflows_v1
from google.cloud.workflows import executions_v1
from google.cloud.workflows.executions_v1 import Execution

# Initialize clients
compute_client = compute_v1.InstancesClient()
firestore_client = firestore.Client()
workflows_client = workflows_v1.WorkflowsClient()
executions_client = executions_v1.ExecutionsClient()

# Configuration
SERVICE_PROJECT_ID = os.environ.get('SERVICE_PROJECT_ID')
TARGET_PROJECT_IDS = os.environ.get('TARGET_PROJECT_IDS', '').split(',')
WORKFLOW_NAME = os.environ.get('WORKFLOW_NAME')
SCAN_INTERVAL_HOURS = int(os.environ.get('SCAN_INTERVAL_HOURS', '24'))
INCLUDE_LABELS = json.loads(os.environ.get('INCLUDE_LABELS', '{}'))
EXCLUDE_LABELS = json.loads(os.environ.get('EXCLUDE_LABELS', '{}'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def discovery_handler(event: Dict[str, Any], context: Any) -> None:
    """
    Main handler for discovery function

    Args:
        event: Pub/Sub event data
        context: Event context
    """
    try:
        # Decode Pub/Sub message
        if 'data' in event:
            message_data = base64.b64decode(event['data']).decode('utf-8')
            message = json.loads(message_data)
        else:
            message = {}

        logger.info(f"Discovery triggered: {message.get('type', 'unknown')}")

        # Discover instances across target projects
        instances_to_scan = []

        for project_id in TARGET_PROJECT_IDS:
            if not project_id.strip():
                continue

            logger.info(f"Discovering instances in project: {project_id}")
            instances = discover_instances_in_project(project_id)
            instances_to_scan.extend(instances)

        logger.info(f"Found {len(instances_to_scan)} instances to potentially scan")

        # Filter instances that need scanning
        filtered_instances = filter_instances_for_scan(instances_to_scan)

        logger.info(f"Filtered to {len(filtered_instances)} instances that need scanning")

        # Trigger scan workflows
        for instance in filtered_instances:
            trigger_scan_workflow(instance)

        logger.info("Discovery completed successfully")

    except Exception as e:
        logger.error(f"Error in discovery handler: {str(e)}", exc_info=True)
        raise


def discover_instances_in_project(project_id: str) -> List[Dict[str, Any]]:
    """
    Discover all VM instances in a project

    Args:
        project_id: GCP project ID

    Returns:
        List of instance metadata
    """
    instances = []

    try:
        # List all zones
        zones_client = compute_v1.ZonesClient()
        zones = zones_client.list(project=project_id)

        for zone in zones:
            zone_name = zone.name

            try:
                # List instances in zone
                request = compute_v1.ListInstancesRequest(
                    project=project_id,
                    zone=zone_name,
                )

                zone_instances = compute_client.list(request=request)

                for instance in zone_instances:
                    # Check if instance should be included based on labels
                    if should_include_instance(instance):
                        instance_data = {
                            'projectId': project_id,
                            'zone': zone_name,
                            'instanceName': instance.name,
                            'instanceId': str(instance.id),
                            'status': instance.status,
                            'machineType': instance.machine_type,
                            'labels': dict(instance.labels) if instance.labels else {},
                            'creationTimestamp': instance.creation_timestamp,
                        }

                        # Determine OS type
                        os_type = detect_os_type(instance)
                        instance_data['osType'] = os_type

                        instances.append(instance_data)

            except Exception as e:
                logger.warning(f"Error listing instances in zone {zone_name}: {str(e)}")
                continue

    except Exception as e:
        logger.error(f"Error discovering instances in project {project_id}: {str(e)}")

    return instances


def should_include_instance(instance: compute_v1.Instance) -> bool:
    """
    Check if instance should be included based on label filters

    Args:
        instance: Compute Engine instance

    Returns:
        True if instance should be included
    """
    instance_labels = dict(instance.labels) if instance.labels else {}

    # Check exclude labels first
    if EXCLUDE_LABELS:
        for key, value in EXCLUDE_LABELS.items():
            if key in instance_labels and instance_labels[key] == value:
                logger.debug(f"Excluding instance {instance.name} due to label {key}={value}")
                return False

    # Check include labels
    if INCLUDE_LABELS:
        for key, value in INCLUDE_LABELS.items():
            if key not in instance_labels or instance_labels[key] != value:
                logger.debug(f"Excluding instance {instance.name} - missing required label {key}={value}")
                return False

    return True


def detect_os_type(instance: compute_v1.Instance) -> str:
    """
    Detect OS type from instance metadata

    Args:
        instance: Compute Engine instance

    Returns:
        'linux' or 'windows'
    """
    # Check disks for OS type
    for disk in instance.disks:
        if disk.boot:
            source = disk.source
            if 'windows' in source.lower():
                return 'windows'

    # Check labels
    if instance.labels:
        labels = dict(instance.labels)
        if 'os' in labels:
            os_label = labels['os'].lower()
            if 'windows' in os_label:
                return 'windows'

    # Default to Linux
    return 'linux'


def filter_instances_for_scan(instances: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """
    Filter instances that need scanning based on last scan time

    Args:
        instances: List of instance metadata

    Returns:
        Filtered list of instances
    """
    filtered = []
    scan_cutoff = datetime.utcnow() - timedelta(hours=SCAN_INTERVAL_HOURS)

    for instance in instances:
        instance_id = instance['instanceId']

        # Check Firestore for last scan time
        try:
            doc_ref = firestore_client.collection('instances').document(instance_id)
            doc = doc_ref.get()

            if doc.exists:
                data = doc.to_dict()
                last_scanned = data.get('lastScanned')

                if last_scanned and last_scanned > scan_cutoff:
                    logger.debug(f"Skipping instance {instance['instanceName']} - recently scanned")
                    continue

            # Update instance metadata in Firestore
            doc_ref.set({
                'projectId': instance['projectId'],
                'zone': instance['zone'],
                'instanceName': instance['instanceName'],
                'instanceId': instance_id,
                'status': instance['status'],
                'osType': instance['osType'],
                'labels': instance['labels'],
                'discoveredAt': datetime.utcnow(),
                'lastScanned': data.get('lastScanned') if doc.exists else None,
                'scanStatus': 'pending',
            }, merge=True)

            filtered.append(instance)

        except Exception as e:
            logger.error(f"Error checking scan status for instance {instance_id}: {str(e)}")
            # Include instance if we can't check status
            filtered.append(instance)

    return filtered


def trigger_scan_workflow(instance: Dict[str, Any]) -> None:
    """
    Trigger Cloud Workflow to scan an instance

    Args:
        instance: Instance metadata
    """
    try:
        # Create execution
        execution = Execution()
        execution.argument = json.dumps(instance)

        request = executions_v1.CreateExecutionRequest(
            parent=WORKFLOW_NAME,
            execution=execution,
        )

        response = executions_client.create_execution(request=request)

        logger.info(f"Triggered workflow for instance {instance['instanceName']}: {response.name}")

        # Update Firestore
        doc_ref = firestore_client.collection('instances').document(instance['instanceId'])
        doc_ref.update({
            'workflowExecutionName': response.name,
            'scanStatus': 'in_progress',
            'scanTriggeredAt': datetime.utcnow(),
        })

    except Exception as e:
        logger.error(f"Error triggering workflow for instance {instance['instanceName']}: {str(e)}")


# Cloud Functions entry point
def main(event, context):
    """Cloud Functions entry point"""
    return discovery_handler(event, context)

"""
Cloud Function to handle image promotion and cleanup
Triggered by Pub/Sub message from validation workflow
"""

import base64
import json
import os
import time
from datetime import datetime
from google.cloud import compute_v1
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration
PROJECT_ID = os.environ.get('GCP_PROJECT', 'sandbox-dev-478813')
ZONE = 'us-central1-a'

# Initialize clients
instances_client = compute_v1.InstancesClient()
images_client = compute_v1.ImagesClient()
zone_operations_client = compute_v1.ZoneOperationsClient()
global_operations_client = compute_v1.GlobalOperationsClient()


def wait_for_zone_operation(operation_name: str, project_id: str, zone: str):
    """Wait for a zone operation to complete"""
    while True:
        operation = zone_operations_client.get(
            project=project_id,
            zone=zone,
            operation=operation_name
        )
        if operation.status == compute_v1.Operation.Status.DONE:
            if operation.error:
                raise Exception(f"Operation failed: {operation.error}")
            return
        time.sleep(2)


def wait_for_global_operation(operation_name: str, project_id: str):
    """Wait for a global operation to complete"""
    while True:
        operation = global_operations_client.get(
            project=project_id,
            operation=operation_name
        )
        if operation.status == compute_v1.Operation.Status.DONE:
            if operation.error:
                raise Exception(f"Operation failed: {operation.error}")
            return
        time.sleep(2)


def create_image_from_vm(instance_name: str, image_name: str, project_id: str) -> str:
    """
    Create an image from a stopped VM instance
    Steps:
    1. Stop the VM
    2. Get the boot disk from the VM
    3. Create image from the disk
    4. Wait for image creation to complete
    5. Return image name (VM deletion happens separately)
    """
    try:
        logger.info(f"Step 1: Stopping VM instance: {instance_name}")
        
        # Step 1: Stop the instance first
        operation = instances_client.stop(
            project=project_id,
            zone=ZONE,
            instance=instance_name
        )
        wait_for_zone_operation(operation.name, project_id, ZONE)
        logger.info(f"✅ VM {instance_name} stopped successfully")
        
        # Step 2: Get the instance to find the boot disk
        logger.info(f"Step 2: Getting boot disk information from VM {instance_name}")
        instance = instances_client.get(
            project=project_id,
            zone=ZONE,
            instance=instance_name
        )
        
        # Get the boot disk - use the full source path directly
        boot_disk_source = None
        for disk in instance.disks:
            if disk.boot:
                boot_disk_source = disk.source
                break
        
        if not boot_disk_source:
            raise Exception(f"Could not find boot disk for instance {instance_name}")
        
        logger.info(f"Found boot disk: {boot_disk_source}")
        
        # Step 3: Create image from the VM's disk
        logger.info(f"Step 3: Creating image {image_name} from disk {boot_disk_source}")
        
        image = compute_v1.Image()
        image.name = image_name
        image.description = f"Promoted image from validated VM {instance_name}"
        image.source_disk = boot_disk_source  # Use full path directly
        image.family = "rhel9-runtime"
        image.labels = {
            "source_image": instance_name,
            "validation_status": "passed",
            "created_by": "promote-cleanup-function"
        }
        
        operation = images_client.insert(
            project=project_id,
            image_resource=image
        )
        
        # Step 4: Wait for image creation to complete
        logger.info(f"Step 4: Waiting for image {image_name} creation to complete...")
        wait_for_global_operation(operation.name, project_id)
        logger.info(f"✅ Image {image_name} created successfully")
        
        # Step 5: Additional wait time to ensure image is fully ready and VM is stable
        logger.info(f"Step 5: Waiting additional 30 seconds to ensure image is fully ready and stable...")
        time.sleep(30)
        logger.info(f"✅ Image {image_name} is fully ready and stable")
        
        return image_name
        
    except Exception as e:
        logger.error(f"Error creating image: {str(e)}")
        raise


def check_vm_exists(instance_name: str, project_id: str) -> bool:
    """Check if VM instance exists"""
    try:
        instance = instances_client.get(
            project=project_id,
            zone=ZONE,
            instance=instance_name
        )
        return instance is not None
    except Exception as e:
        if "not found" in str(e).lower() or "NOT_FOUND" in str(e):
            return False
        raise


def wait_for_vm_stable(instance_name: str, project_id: str, max_wait_seconds: int = 60):
    """Wait for VM to be in a stable state (STOPPED or RUNNING) before deletion"""
    logger.info(f"Waiting for VM {instance_name} to be in stable state...")
    start_time = time.time()
    
    while time.time() - start_time < max_wait_seconds:
        try:
            instance = instances_client.get(
                project=project_id,
                zone=ZONE,
                instance=instance_name
            )
            
            status = instance.status
            logger.info(f"VM {instance_name} current status: {status}")
            
            # VM is stable if it's STOPPED or RUNNING (not in transition)
            if status in [compute_v1.Instance.Status.TERMINATED, compute_v1.Instance.Status.STOPPED, compute_v1.Instance.Status.RUNNING]:
                logger.info(f"✅ VM {instance_name} is in stable state: {status}")
                return True
            else:
                logger.info(f"VM {instance_name} is in transition state: {status}, waiting...")
                time.sleep(5)
        except Exception as e:
            if "not found" in str(e).lower() or "NOT_FOUND" in str(e):
                logger.warning(f"VM {instance_name} not found, may already be deleted")
                return False
            raise
    
    logger.warning(f"VM {instance_name} did not reach stable state within {max_wait_seconds} seconds")
    return False


def delete_vm(instance_name: str, project_id: str, max_retries: int = 3):
    """Delete the validation VM instance with retry logic"""
    for attempt in range(1, max_retries + 1):
        try:
            # First, check if VM exists
            if not check_vm_exists(instance_name, project_id):
                logger.info(f"VM {instance_name} does not exist, skipping deletion")
                return
            
            # Wait for VM to be in stable state
            if not wait_for_vm_stable(instance_name, project_id):
                logger.warning(f"VM {instance_name} is not in stable state, but attempting deletion")
            
            logger.info(f"Attempt {attempt}/{max_retries}: Deleting VM instance: {instance_name}")
            
            # Try to stop the VM first if it's running
            try:
                instance = instances_client.get(
                    project=project_id,
                    zone=ZONE,
                    instance=instance_name
                )
                if instance.status == compute_v1.Instance.Status.RUNNING:
                    logger.info(f"Stopping VM {instance_name} before deletion...")
                    stop_operation = instances_client.stop(
                        project=project_id,
                        zone=ZONE,
                        instance=instance_name
                    )
                    wait_for_zone_operation(stop_operation.name, project_id, ZONE)
                    logger.info(f"VM {instance_name} stopped successfully")
            except Exception as stop_error:
                if "not found" not in str(stop_error).lower():
                    logger.warning(f"Could not stop VM: {stop_error}, proceeding with deletion")
            
            # Forcefully delete the VM (even if in transition state)
            logger.info(f"Forcefully deleting VM {instance_name}...")
            try:
                operation = instances_client.delete(
                    project=project_id,
                    zone=ZONE,
                    instance=instance_name
                )
                
                # Wait for deletion with longer timeout
                logger.info(f"Waiting for VM deletion to complete...")
                wait_for_zone_operation(operation.name, project_id, ZONE)
                logger.info(f"✅ VM {instance_name} deleted successfully")
                
                # Additional wait to ensure VM is fully terminated
                logger.info(f"Waiting 10 seconds to ensure VM is fully terminated...")
                time.sleep(10)
                
                return
            except Exception as delete_error:
                # If delete fails, try to force stop and delete again
                error_str = str(delete_error).lower()
                if "not found" not in error_str:
                    logger.warning(f"First delete attempt failed: {delete_error}, trying force stop and delete...")
                    try:
                        # Force stop if still running
                        try:
                            instance = instances_client.get(project=project_id, zone=ZONE, instance=instance_name)
                            if instance.status in [compute_v1.Instance.Status.RUNNING, compute_v1.Instance.Status.STOPPING]:
                                logger.info(f"Force stopping VM {instance_name}...")
                                stop_op = instances_client.stop(project=project_id, zone=ZONE, instance=instance_name)
                                wait_for_zone_operation(stop_op.name, project_id, ZONE)
                                time.sleep(5)
                        except:
                            pass
                        
                        # Try delete again
                        operation = instances_client.delete(project=project_id, zone=ZONE, instance=instance_name)
                        wait_for_zone_operation(operation.name, project_id, ZONE)
                        logger.info(f"✅ VM {instance_name} force deleted successfully")
                        time.sleep(10)
                        return
                    except Exception as force_error:
                        if "not found" not in str(force_error).lower():
                            raise
                        logger.info(f"VM {instance_name} already deleted")
                        return
                else:
                    logger.info(f"VM {instance_name} not found, already deleted")
                    return
            
        except Exception as e:
            error_str = str(e).lower()
            if "not found" in error_str or "not_found" in error_str:
                logger.info(f"VM {instance_name} not found, may already be deleted")
                return
            
            if attempt < max_retries:
                wait_time = attempt * 5
                logger.warning(f"Attempt {attempt} failed: {e}. Retrying in {wait_time} seconds...")
                time.sleep(wait_time)
            else:
                logger.error(f"Failed to delete VM {instance_name} after {max_retries} attempts: {e}")
                raise


def promote_cleanup(event, context):
    """
    Cloud Function entry point
    Triggered by Pub/Sub message
    """
    try:
        # Decode Pub/Sub message
        if 'data' in event:
            message_data = base64.b64decode(event['data']).decode('utf-8')
            logger.info(f"Received message data: {message_data}")
        
        # Extract attributes from Pub/Sub message
        attributes = event.get('attributes', {})
        
        image_id = attributes.get('image_id', '')
        scan_result = attributes.get('scan_result', '')
        validation_instance = attributes.get('validation_instance', '')
        skip_destroy = attributes.get('skip_destroy', 'false').lower() == 'true'
        skip_promotion = attributes.get('skip_promotion', 'false').lower() == 'true'
        
        logger.info(f"Processing promotion/cleanup:")
        logger.info(f"  image_id: {image_id}")
        logger.info(f"  scan_result: {scan_result}")
        logger.info(f"  validation_instance: {validation_instance}")
        logger.info(f"  skip_destroy: {skip_destroy}")
        logger.info(f"  skip_promotion: {skip_promotion}")
        
        # Validate required fields
        if not validation_instance:
            logger.warning("No validation_instance provided, skipping")
            return
        
        if scan_result != 'Pass':
            logger.warning(f"Scan result is {scan_result}, not promoting")
            return
        
        promoted_image = None
        
        # Step 1: Stop VM, Create image from temp VM, Wait for image creation (if not skipped)
        if not skip_promotion:
            timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')
            promoted_image_name = f"{image_id}-promoted-{timestamp}"
            
            logger.info(f"=== Starting Image Promotion ===")
            logger.info(f"Image name: {promoted_image_name}")
            logger.info(f"Source VM: {validation_instance}")
            
            # This function will:
            # 1. Stop the VM
            # 2. Create image from the stopped VM's disk
            # 3. Wait for image creation to complete
            promoted_image = create_image_from_vm(
                validation_instance,
                promoted_image_name,
                PROJECT_ID
            )
            logger.info(f"✅ Promoted image created successfully: {promoted_image}")
        else:
            logger.info("Image promotion skipped (skip_promotion=true)")
        
        # Step 2: Delete the validation VM instance (only after image is fully created and ready)
        if not skip_destroy:
            logger.info(f"=== Starting VM Cleanup ===")
            logger.info(f"Image promotion completed. Now deleting validation VM: {validation_instance}")
            
            # Additional wait to ensure image is fully ready before VM deletion
            if promoted_image:
                logger.info(f"Waiting 5 seconds to ensure promoted image {promoted_image} is fully ready...")
                time.sleep(5)
            
            delete_vm(validation_instance, PROJECT_ID)
            logger.info(f"✅ Validation VM cleaned up: {validation_instance}")
        else:
            logger.info("VM cleanup skipped (skip_destroy=true)")
        
        logger.info("✅ Promotion and cleanup completed successfully")
        
        return {
            'status': 'success',
            'promoted_image': promoted_image,
            'validation_instance': validation_instance,
            'timestamp': datetime.now().isoformat()
        }
        
    except Exception as e:
        logger.error(f"Error in promote_cleanup function: {str(e)}")
        raise


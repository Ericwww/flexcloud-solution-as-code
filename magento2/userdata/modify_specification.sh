#!/bin/bash
sleep 600

PROJECT_ID=$(curl http://169.254.169.254/openstack/latest/meta_data.json | grep -oP '"project_id": "\K[^"]+')
export PROJECT_ID
REGION=$(curl http://169.254.169.254/openstack/latest/meta_data.json | grep -oP '"region_id": "\K[^"]+')
export REGION
UUID=$(curl http://169.254.169.254/openstack/latest/meta_data.json | grep -oP '"uuid": "\K[^"]+')
export UUID

# Install KooCLI
curl -sSL https://solution-as-code-w8das.obs.eu-central-6001.apistack.one.hu/magento2-base-ecs/hcloud_install.sh -o ./hcloud_install.sh && bash ./hcloud_install.sh -y
hcloud configure set --cli-agree-privacy-statement=true

while true
do
    echo "Check if the image packaging of the magento server is complete..."
    image_id=$(hcloud IMS ListImages --cli-region="$REGION" --name="$1" | grep -oP '"id": "\K[^"]+')
    status=$(hcloud IMS ListImages --cli-region="$REGION" --name="$1" | grep -oP '"status": "\K[^"]+')
    flag=$(hcloud IMS ListImages --cli-region="$REGION" --name="$1" | grep "__whole_image_az")
    if [[ -n "$image_id" && "$status" = "active" && ! "$flag" ]]
    then
        echo "Check passed.Starting to modify the specication..."
        export IMAGE_ID=$image_id
        break
    else
        echo "Waiting for the image packaging of the magento server to be completed, and retry in 60 seconds..."
        sleep 60
    fi
done

# Change os
hcloud ECS ChangeServerOsWithCloudInit \
--cli-region="$REGION" \
--server_id="$UUID" \
--os-change.mode="withStopServer" \
--os-change.imageid="$IMAGE_ID" \
--os-change.metadata.user_data="JTIzJTIxL2Jpbi9iYXNoJTBBZWNobyUyMCUyN3Jvb3QlM0ElMjQyJTI3JTIwJTdDJTIwY2hwYXNzd2Q="
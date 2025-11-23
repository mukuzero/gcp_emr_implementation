#!/bin/bash
set -e

BUCKET_NAME=$1
REGION=$2

if [ -z "$BUCKET_NAME" ] || [ -z "$REGION" ]; then
  echo "Usage: $0 <BUCKET_NAME> <REGION>"
  exit 1
fi

echo "Checking if bucket gs://$BUCKET_NAME exists..."

if ! gcloud storage buckets describe gs://$BUCKET_NAME > /dev/null 2>&1; then
  echo "Bucket gs://$BUCKET_NAME does not exist. Creating it..."
  gcloud storage buckets create gs://$BUCKET_NAME --location=$REGION
  
  echo "Enabling versioning on gs://$BUCKET_NAME..."
  gcloud storage buckets update gs://$BUCKET_NAME --versioning-enabled
  
  echo "Bucket created successfully."
else
  echo "Bucket gs://$BUCKET_NAME already exists."
fi

#!/bin/bash
REQUEST_FILE=$1
REQUEST_ID=$(jq -r '.requestId' $REQUEST_FILE)
REQUEST_TYPE=$(jq -r '.type' $REQUEST_FILE)
REQUEST_NAME=$(jq -r '.name' $REQUEST_FILE)

if [ "$REQUEST_TYPE" == "group" ]; then
  NAMESPACE="${REQUEST_NAME}-project"
else
  NAMESPACE="user-${REQUEST_NAME}-project"
fi

mkdir -p "generated/${NAMESPACE}"

# Namespace oluştur
export NAMESPACE REQUEST_ID OWNER=$REQUEST_NAME
envsubst < ../templates/namespace.yaml > "generated/${NAMESPACE}/namespace.yaml"

# Workbench'leri işle
jq -c '.resources.workbenches[]?' $REQUEST_FILE | while read WB; do
  NOTEBOOK_NAME=$(echo $WB | jq -r '.name')
  IMAGE=$(echo $WB | jq -r '.image')
  SIZE=$(echo $WB | jq -r '.size')
  STORAGE=$(echo $WB | jq -r '.storage // "20Gi"')
  
  case $SIZE in
    "small") CPU=1; MEM=4 ;;
    "medium") CPU=2; MEM=8 ;;
    "large") CPU=4; MEM=16 ;;
    *) CPU=1; MEM=4 ;;
  esac
  
  export NOTEBOOK_NAME IMAGE CPU_LIMIT=$CPU CPU_REQUEST=$CPU \
         MEMORY_LIMIT=$MEM MEMORY_REQUEST=$MEM STORAGE_SIZE=$STORAGE
  
  envsubst < ../templates/workbench.yaml > "generated/${NAMESPACE}/${NOTEBOOK_NAME}-notebook.yaml"
done

# Kustomization dosyasını oluştur
cat > "generated/${NAMESPACE}/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- namespace.yaml
$(ls generated/${NAMESPACE}/*.yaml | grep -v kustomization | xargs -n1 basename | awk '{print "- " $0}')

commonLabels:
  request-id: "${REQUEST_ID}"
  owner: "${REQUEST_NAME}"
EOF

echo "Resources generated in generated/${NAMESPACE}"

#!/bin/bash
# RHOAS GitOps Otomasyon Kurulumu

# 1. Temel dizin yapısını oluştur
mkdir -p rhoas-gitops/{requests,templates/{model-serving},scripts,generated}

# 2. Örnek request dosyalarını oluştur
cat > rhoas-gitops/requests/sample-group-request.json <<'EOL'
{
  "requestId": "group-123",
  "type": "group",
  "name": "data-science-team-a",
  "resources": {
    "workbenches": [
      {
        "name": "team-notebook-1",
        "size": "medium",
        "image": "s2i-minimal-notebook",
        "storage": "50Gi"
      },
      {
        "name": "team-notebook-2",
        "size": "large",
        "image": "pytorch-gpu-notebook",
        "storage": "100Gi"
      }
    ],
    "models": [
      {
        "name": "fraud-detection",
        "runtime": "ovms",
        "format": "onnx",
        "size": "small"
      }
    ]
  }
}
EOL

cat > rhoas-gitops/requests/sample-user-request.json <<'EOL'
{
  "requestId": "user-456",
  "type": "user",
  "name": "johndoe",
  "resources": {
    "workbenches": [
      {
        "name": "personal-notebook",
        "size": "medium",
        "image": "tensorflow-notebook",
        "storage": "30Gi"
      }
    ]
  }
}
EOL

# 3. Template dosyalarını oluştur
cat > rhoas-gitops/templates/namespace.yaml <<'EOL'
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
  labels:
    opendatahub.io/dashboard: "true"
    owner: ${OWNER}
    request-id: ${REQUEST_ID}
    ${MODELMESH_LABEL}
EOL

cat > rhoas-gitops/templates/workbench.yaml <<'EOL'
apiVersion: kubeflow.org/v1
kind: Notebook
metadata:
  name: ${NOTEBOOK_NAME}
  namespace: ${NAMESPACE}
spec:
  template:
    spec:
      containers:
      - name: ${NOTEBOOK_NAME}
        image: ${IMAGE}
        resources:
          limits:
            cpu: "${CPU_LIMIT}"
            memory: ${MEMORY_LIMIT}Gi
          requests:
            cpu: "${CPU_REQUEST}"
            memory: ${MEMORY_REQUEST}Gi
        volumeMounts:
        - mountPath: /opt/app-root/src
          name: ${NOTEBOOK_NAME}-pvc
      volumes:
      - name: ${NOTEBOOK_NAME}-pvc
        persistentVolumeClaim:
          claimName: ${NOTEBOOK_NAME}-pvc
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${NOTEBOOK_NAME}-pvc
  namespace: ${NAMESPACE}
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: ${STORAGE_SIZE}
EOL

# 4. Script dosyalarını oluştur
cat > rhoas-gitops/scripts/process-request.sh <<'EOL'
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
EOL

chmod +x rhoas-gitops/scripts/process-request.sh

# 5. README dosyası oluştur
cat > rhoas-gitops/README.md <<'EOL'
# OpenShift AI GitOps Otomasyonu

## Kurulum
1. Repoyu klonlayın:
   ```bash
   git clone <repo-url>
   cd rhoas-gitops
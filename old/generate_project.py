import os
import shutil
import json

# Ayarlar
TEMPLATE_PATH = "overlays/template"
OVERLAYS_PATH = "overlays"
APPS_PATH = "apps"
APP_TEMPLATE = """apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: {username}-ds-project
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: 'https://github.com/gultekinkeles/rhoai-gitops.git'
    path: overlays/gultekinkeles
    targetRevision: main
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: {username}-project
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
"""

# Kustomization başlangıç şablonu
KUSTOMIZATION_TEMPLATE = """resources:
"""

def load_request(json_file):
    with open(json_file) as f:
        return json.load(f)

def create_overlay(username, components):
    user_path = os.path.join(OVERLAYS_PATH, username)
    if os.path.exists(user_path):
        print(f"{username} dizini zaten var. Üzerine yazılıyor...")
        shutil.rmtree(user_path)
    shutil.copytree(TEMPLATE_PATH, user_path)

    # Dosya içeriklerinde username ve namespace değiştir
    for file in os.listdir(user_path):
        path = os.path.join(user_path, file)
        with open(path, "r") as f:
            content = f.read()
        content = content.replace("__USERNAME__", username).replace("__NAMESPACE__", f"{username}-project")
        with open(path, "w") as f:
            f.write(content)

    # Kustomization yaz
    kustomization = KUSTOMIZATION_TEMPLATE
    for c in components:
        kustomization += f"  - {c}.yaml\n"
    with open(os.path.join(user_path, "kustomization.yaml"), "w") as f:
        f.write(kustomization)

def create_application_manifest(username):
    app_content = APP_TEMPLATE.format(username=username)
    with open(os.path.join(APPS_PATH, f"{username}-app.yaml"), "w") as f:
        f.write(app_content)

def main():
    request = load_request("project_request.json")
    username = request["username"]
    components = request["components"]

    create_overlay(username, components)
    create_application_manifest(username)

    print(f"[OK] {username} için proje yapısı oluşturuldu.")

if __name__ == "__main__":
    main()

# Talos config patches

Every `*.yaml` here is applied by `talos.tf`, in filename order:

- `common/`: all nodes
- `controlplane/`, `worker/`: nodes with that role (create the folder if needed)

Files are Terraform templates; the only variable is `${installer_image}`.
CI (`.github/workflows/ci.yml`) runs `talosctl validate` on a config generated
from these same files.

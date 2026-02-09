# orcd-zfs-rpm-builder
Repo setup for custom version rpm build for zfs environment

## GitHub Actions runner
Workflows run on a self-hosted runner with labels `self-hosted` and `ORCD-StorEC2`.

On the EC2 instance:
- Install and register a GitHub Actions runner for this repo.
- Add the runner label `ORCD-StorEC2`.

The workflows installs Apptainer and build the RHEL9 container image (`rhel9.sif`) and ZFS RPMs, then publish the RPMs as release.

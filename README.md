# orcd-zfs-rpm-builder
Repo setup for custom version rpm build for zfs environment

## GitHub Actions runner
Workflows run on a self-hosted runner with labels `self-hosted` and `orcd-stor-ec2`.

On the EC2 instance:
- Install and register a GitHub Actions runner for this repo.
- Add the runner label `orcd-stor-ec2`.
- Ensure `apt-get` and `sudo` are available (Ubuntu 22.04 is fine).

The workflows install Apptainer and build the RHEL9 container image (`rhel9.sif`) and ZFS RPMs, then upload the RPMs as workflow artifacts.

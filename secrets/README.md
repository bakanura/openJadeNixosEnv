Custom UI translation secrets

This repo can keep the DeepL key per host in `secrets/<hostname>/deepl-api-key.age`.

Workflow:

1. Put your plaintext DeepL key in `~/.config/deepl-api-key`.
2. Run `custom-ui-translation-bootstrap-secret`.
3. Commit the generated `secrets/<hostname>/deepl-api-key.age` and `ssh_host_ed25519_key.pub`.
4. Rebuild the host.

At activation time, the custom UI translation module decrypts the host-specific `.age` file with `/etc/ssh/ssh_host_ed25519_key` into `/run/custom-ui-translation/deepl-api-key` and points the custom UI scripts at that runtime path automatically.

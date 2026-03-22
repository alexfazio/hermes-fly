# Uninstall

Steps to completely remove hermes-fly and its Fly.io resources.

## 1. Destroy Fly.io Apps

Remove your deployed Hermes instances first. This deletes the app, volumes, and secrets.

Using hermes-fly:

```bash
hermes-fly destroy
```

Or specify an app by name:

```bash
hermes-fly destroy -a your-app-name
```

If hermes-fly is already removed, use the Fly CLI directly:

```bash
fly apps destroy your-app-name
```

If you have multiple apps, repeat for each one. Check your config file for the list:

```bash
cat ~/.hermes-fly/config.yaml
```

## 2. Remove the hermes-fly Binary

Delete the `hermes-fly` script from wherever it was installed:

```bash
# Fresh user-local installs (default)
rm ~/.local/bin/hermes-fly
rm -rf ~/.local/share/hermes-fly

# macOS fresh installs store support files in Application Support
rm -rf ~/Library/Application\ Support/hermes-fly

# Older system-wide installs may still live here
rm /usr/local/bin/hermes-fly
rm -rf /usr/local/lib/hermes-fly

# If installed elsewhere, find it first
which hermes-fly
```

If hermes-fly was cloned as a git repository, remove the entire directory:

```bash
rm -rf /path/to/hermes-fly
```

## 3. Remove the Config Directory

Delete the local configuration directory:

```bash
rm -rf ~/.hermes-fly
```

This removes `config.yaml` (app tracking). No secrets stored here.

The log file `hermes-fly.log` is written to the working directory where you run
`hermes-fly`, not `~/.hermes-fly`. Delete it from there if needed.

## 4. Verify Removal

Confirm that no Fly.io resources remain:

```bash
# List your Fly apps -- none should be hermes-related
fly apps list

# Confirm the binary is gone
which hermes-fly
# Should print "hermes-fly not found"

# Confirm the config directory is gone
ls ~/.hermes-fly
# Should print "No such file or directory"
```

## Notes

- **flyctl is not removed.** To uninstall flyctl, see the
  [Fly.io community guide](https://community.fly.io/t/how-to-uninstall-or-remove-flyctl/7155).
- **Fly.io account is not affected.** Destroying apps does not close your account.
- Destroying an app deletes all volume data. Ensure you don't need anything
  in `/root/.hermes` on the Fly Machine before proceeding.

## References

- [Fly.io community guide: uninstall flyctl](https://community.fly.io/t/how-to-uninstall-or-remove-flyctl/7155)

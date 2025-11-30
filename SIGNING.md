# Code Signing FloatMD

To persist accessibility permissions across rebuilds, you need to sign the app with a consistent certificate.

## Create a Self-Signed Certificate (One-Time Setup)

1. **Open Keychain Access**
   - Press `Cmd+Space`, type "Keychain Access", press Enter

2. **Create Certificate**
   - Menu: `Keychain Access` → `Certificate Assistant` → `Create a Certificate...`

3. **Configure Certificate**
   - **Name:** `FloatNote Developer`
   - **Identity Type:** `Self Signed Root`
   - **Certificate Type:** `Code Signing`
   - Check ✓ `Let me override defaults`
   - Click `Continue`

4. **Accept Defaults**
   - Click `Continue` through all the following screens (defaults are fine)
   - Click `Done` when complete

5. **Trust the Certificate**
   - In Keychain Access, find `FloatNote Developer` in the login keychain
   - Double-click it to open details
   - Expand the `Trust` section
   - Set `Code Signing` to `Always Trust`
   - Close the window (you'll be prompted for your password)

## Build with Your Certificate

Option A - Set environment variable each time:
```bash
FLOATMD_SIGN_IDENTITY="FloatNote Developer" ./build_app.sh
```

Option B - Add to your shell profile (~/.zshrc or ~/.bashrc):
```bash
export FLOATMD_SIGN_IDENTITY="FloatNote Developer"
```
Then just run `./build_app.sh` normally.

## Verify It Works

After building, check the signature:
```bash
codesign -dv /Applications/FloatMD.app
```

You should see `Authority=FloatNote Developer` in the output.

## Grant Permissions (One Time)

1. Open FloatMD
2. Grant Accessibility permission when prompted
3. Future rebuilds will retain this permission

## Troubleshooting

**"FloatNote Developer" not found:**
- Make sure the certificate name matches exactly
- Check it exists: `security find-identity -v -p codesigning`

**Still asking for permissions:**
- Remove FloatMD from System Settings → Privacy & Security → Accessibility
- Rebuild and re-add it

**Certificate expired:**
- Delete old certificate from Keychain Access
- Create a new one following steps above

- It communicates through standard input/output .
- Uses the Unix username of the process owner for license validation and tool operations.
- simplifies setup by eliminating the need for authentication configuration.

---

### Prerequisites
- SPF installed (per the Synopsys.ai Copilot Knowledge Assistant Administrator Guide).
- Endpoint configuration file (`generic_tool.yaml` per the Synopsys.ai Copilot Knowledge Assistant Administrator Guide).

---

### Configuring MCP in VSCode
Configure the MCP server in Visual Studio Code (VSCode) to connect and use Copilot features. This setup allows you to integrate Copilot with your development environment.

#### Set Execute Permissions for the Executable
If you see a "Permission denied" error when running the executable, set execute permissions.
1. Open a terminal.
2. Enter the following command:
```bash
chmod +x $SNPSAI_COPILOT_HOME/linux64/copilot/bin/snpsai_copilot_mcp_exec
```

---

### VSCode Configuration
Different MCP clients use different configuration syntax. The following uses VSCode syntax:
1. Open your VSCode settings.
2. Update your configuration as follows:
```json
{
  "servers": {
    "snps": {
      "command": "<REPLACE_WITH_YOUR_SNPSAI_COPILOT_HOME>/linux64/copilot/bin/snpsai_copilot_mcp_exec",
      "env": {
        "SNPSAI_COPILOT_MCP_TRANSPORT": "stdio",
        "SNPSAI_COPILOT_CONFIG_YAML": "/your/path/to/generic_tool.yaml",
        "SNPSLMD_LICENSE_FILE": "a@abc123:b@xyz123",
        "SNPSAI_COPILOT_LOGLEVEL": "INFO",
        "SNPSAI_COPILOT_CENTRAL_LOGGING_FILE": "/path/to/your/mcp/log"
      }
    }
  }
}
```
3. Replace `<REPLACE_WITH_YOUR_SNPSAI_COPILOT_HOME>` with your actual Copilot home directory.
4. Update the `generic_tool.yaml` path to your configuration file.
5. Set the license file and log file paths as required.
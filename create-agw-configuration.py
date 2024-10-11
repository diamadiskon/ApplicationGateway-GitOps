import argparse
import json
import os
import subprocess
import sys

### ARGUMENTS ###
parser = argparse.ArgumentParser(description="Please do not mess up this Script!")
parser.add_argument(
    "-f", "--file", dest="file", help="The json file to use", type=str, required=True
)
args = parser.parse_args()
#################


def check_variable(variable, data, mandatory=True):
    # Check if the variable is present in the loaded data
    if variable in data:
        print(
            f"[=] Info: '{variable}' is present in the json file with a value of {data[variable]}"
        )
        print(
            f"##vso[task.setvariable variable={variable};isOutput=true;]{data[variable]}",
            file=sys.stderr,
        )
        return data[variable]
    else:
        if mandatory is True:
            print(
                f"[-] Error: You didn't provide {variable} inside the json, which is mandatory. Exiting with status code 1"
            )
            sys.exit(1)
        else:
            print(
                f"[-] You didn't provide {variable} inside the json, it's optional, we skip it"
            )


def add_backend_pool(name, agw_id, ip_addresses, fqdns):
    backend_pool_initial_string = """
{
    "backendAddressPools": [
        {
            "name": "{name}BackendPool",
            "id": "{gateway_id}/backendAddressPools/{name}BackendPool",
            "properties": {
                "backendAddresses": []
            },
            "type": "Microsoft.Network/applicationGateways/backendAddressPools"
        }
    ]
}
"""
    backend_pool_data = json.loads(backend_pool_initial_string)
    backend_pool_data["backendAddressPools"][0]["name"] = f"{name}BackendPool"
    backend_pool_data["backendAddressPools"][0]["id"] = (
        f"{agw_id}/backendAddressPools/{name}BackendPool"
    )
    backend_addresses = backend_pool_data["backendAddressPools"][0]["properties"][
        "backendAddresses"
    ]

    if fqdns:
        for fqdn in fqdns:
            backend_addresses.append({"fqdn": fqdn})
        return backend_pool_data
    else:
        for ip in ip_addresses:
            backend_addresses.append({"ipAddress": ip})
        return backend_pool_data


def add_backend_http_settings(name, agw_id, app_name):
    backend_http_settings_initial_string = """
{
    "backendHttpSettingsCollection": [
    {
      "name": "{name}BackendHttpsSettings",
      "id": "{agw_id}/backendHttpSettingsCollection/{name}BackendHttpsSettings",
      "properties": {
        "port": 443,
        "protocol": "Https",
        "cookieBasedAffinity": "Disabled",
        "hostName": "{app_name}",
        "pickHostNameFromBackendAddress": false,
        "affinityCookieName": "ApplicationGatewayAffinity",
        "path": "/",
        "requestTimeout": 120,
        "probe": {
          "id": "{agw_id}/probes/{name}HP"
        },
        "pathRules": [
          {
            "id": "{agw_id}/urlPathMaps/{name}HttpsRule/pathRules/{app_name}"
          }
        ]
      },
      "type": "Microsoft.Network/applicationGateways/backendHttpSettingsCollection"
    }
  ]
}
"""
    backend_http_settings_data = json.loads(backend_http_settings_initial_string)
    backend_http_settings_data["backendHttpSettingsCollection"][0]["name"] = (
        f"{name}BackendHttpsSettings"
    )
    backend_http_settings_data["backendHttpSettingsCollection"][0]["id"] = (
        f"{agw_id}/backendHttpSettingsCollection/{name}BackendHttpsSettings"
    )
    backend_http_settings_data["backendHttpSettingsCollection"][0]["properties"][
        "hostName"
    ] = f"{app_name}"
    backend_http_settings_data["backendHttpSettingsCollection"][0]["properties"][
        "probe"
    ]["id"] = f"{agw_id}/probes/{name}HP"
    backend_http_settings_data["backendHttpSettingsCollection"][0]["properties"][
        "pathRules"
    ][0]["id"] = f"{agw_id}/urlPathMaps/{name}HttpsRule/pathRules/{app_name}"
    return backend_http_settings_data


def add_health_probe(name, agw_id, app_name, healthcheck_path):
    health_probe_initial_string = """
{
    "probes": [
    {
      "name": "{name}HP",
      "id": "{agw_id}/probes/{name}HP",
      "properties": {
        "protocol": "Https",
        "host": "{app_name}",
        "path": "{healthcheck_path}",
        "interval": 30,
        "timeout": 30,
        "unhealthyThreshold": 3,
        "pickHostNameFromBackendHttpSettings": false,
        "minServers": 0,
        "match": {
          "body": "",
          "statusCodes": [
            "200-399"
          ]
        }
      },
      "type": "Microsoft.Network/applicationGateways/probes"
    }
  ]
}
"""
    health_probe_data = json.loads(health_probe_initial_string)
    health_probe_data["probes"][0]["name"] = f"{name}HP"
    health_probe_data["probes"][0]["id"] = f"{agw_id}/probes/{name}HP"
    health_probe_data["probes"][0]["properties"]["host"] = f"{app_name}"
    health_probe_data["probes"][0]["properties"]["path"] = f"{healthcheck_path}"
    return health_probe_data


def add_routing_rule(name, agw_id):
    routing_rule_initial_string = """
{
   "requestRoutingRules": [
    {
      "name": "{name}HttpsRule",
      "id": "{agw_id}/requestRoutingRules{name}HttpsRule",
      "properties": {
        "ruleType": "PathBasedRouting",
        "priority": 10,
        "listener": {
          "id": "{agw_id}/listeners/{name}HttpsListener"
        },
        "urlPathMap": {
          "id": "{agw_id}/urlPathMaps/{name}HttpsRule"
        }
      },
      "type": "Microsoft.Network/applicationGateways/requestRoutingRules"
    }
  ]
}
"""
    routing_rule_data = json.loads(routing_rule_initial_string)
    routing_rule_data["requestRoutingRules"][0]["name"] = f"{name}HttpsRule"
    routing_rule_data["requestRoutingRules"][0]["id"] = (
        f"{agw_id}/requestRoutingRules{name}HttpsRule"
    )
    routing_rule_data["requestRoutingRules"][0]["properties"]["listener"]["id"] = (
        f"{agw_id}/listeners/{name}HttpsListener"
    )
    routing_rule_data["requestRoutingRules"][0]["properties"]["urlPathMap"]["id"] = (
        f"{agw_id}/urlPathMaps/{name}HttpsRule"
    )
    return routing_rule_data


def add_path_rules(name, agw_id, path, appgw_rule_name):
    path_rules_initial_string = """
{
   "pathRoutes": [
        {
          "pathRules": [
            {
              "path": "{path}",
              "name": "{appgw_rule_name}",
              "backendAddressPool": {
                "id": "{agw_id}/backendAddressPools/{name}BackendPool"
              },
              "backendHttpSettings": {
                "id": "{agw_id}/backendHttpSettingsCollection/{name}BackendHttpsSettings"
              }
            }
          ],
          "urlPathMapName": {
            "name": "{appgw_rule_name}HttpsRule"
          }
        }
      ]
}
"""
    path_rules_data = json.loads(path_rules_initial_string)
    path_rules_data["pathRoutes"][0]["pathRules"][0]["path"] = f"{path}"
    path_rules_data["pathRoutes"][0]["pathRules"][0]["name"] = f"{appgw_rule_name}"
    path_rules_data["pathRoutes"][0]["pathRules"][0]["backendAddressPool"]["id"] = (
        f"{agw_id}/backendAddressPools/{name}BackendPool"
    )
    path_rules_data["pathRoutes"][0]["pathRules"][0]["backendHttpSettings"]["id"] = (
        f"{agw_id}/backendHttpSettingsCollection/{name}BackendHttpsSettings"
    )
    path_rules_data["pathRoutes"][0]["urlPathMapName"]["name"] = (
        f"{appgw_rule_name}HttpsRule"
    )
    return path_rules_data


def main():
    ### VARIABLES CREATION ###
    file_path = args.file
    if os.path.exists(file_path):
        print(f"[=] Info: File exist at the given path '{file_path}'.")
        ### Read Json File ###
        with open(file_path, "r") as file:
            data = json.load(file)

        print(f"[=] Info: RUNNING PYTHON FROM: {sys.executable}")
        ### Necessary for Pipelines / Configuration
        fqdns = check_variable(variable="fqdns", data=data, mandatory=False)

        ip_addresses = check_variable(
            variable="ip_addresses", data=data, mandatory=False
        )
        healthcheck_path = check_variable(
            variable="healthcheck_path", data=data, mandatory=True
        )
        application_path = check_variable(
            variable="application_path", data=data, mandatory=True
        )
        name = check_variable(variable="name", data=data, mandatory=True)
        appgw_rule_name = check_variable(
            variable="appgw_rule_name", data=data, mandatory=True
        )
        application_name = check_variable(
            variable="application_name", data=data, mandatory=True
        )
        application_gateway = check_variable(
            variable="application_gateway", data=data, mandatory=True
        )
        resource_group = check_variable(
            variable="resource_group", data=data, mandatory=True
        )
        subscription = check_variable(
            variable="subscription", data=data, mandatory=True
        )

        application_gateway_command = f"az network application-gateway show --resource-group {resource_group} --subscription {subscription} --name {application_gateway} --query id --output tsv"
        application_gateway_output = subprocess.check_output(
            application_gateway_command, shell=True
        )
        application_gateway_id = (
            application_gateway_output.decode("utf-8").strip('"').strip("\n")
        )
        print(application_gateway_id)

        print("[=] CONFIGURATION FOR BACKEND POOL")
        backend_pool_json = add_backend_pool(
            name=name,
            agw_id=application_gateway_id,
            ip_addresses=ip_addresses,
            fqdns=fqdns,
        )
        print("")
        print("[=] CONFIGURATION FOR HTTP SETTINGS")
        backend_http_settings_json = add_backend_http_settings(
            name=name, agw_id=application_gateway_id, app_name=application_name
        )
        print("")
        print("[=] CONFIGURATION FOR HEALTH PROBE")
        health_probe_json = add_health_probe(
            name=name,
            agw_id=application_gateway_id,
            app_name=application_name,
            healthcheck_path=healthcheck_path,
        )
        print("")
        print("[=] CONFIGURATION FOR ROUTING RULE")
        routing_rule_json = add_routing_rule(name=name, agw_id=application_gateway_id)
        print("")
        print("[=] CONFIGURATION FOR PATH RULE")
        path_rules_json = add_path_rules(
            name=name,
            agw_id=application_gateway_id,
            path=application_path,
            appgw_rule_name=appgw_rule_name,
        )

        final_dict_data = {
            **backend_pool_json,
            **backend_http_settings_json,
            **health_probe_json,
            **routing_rule_json,
            **path_rules_json,
        }

        # Write merged dictionary to a file
        with open("agw-configuration.json", "w") as file:
            json.dump(final_dict_data, file, indent=4)

        print("Merged JSON has been written to agw-configuration.json")
    else:
        print(f"[-] Error: File does not exist at the given path '{file_path}'.")
        sys.exit(1)


if __name__ == "__main__":
    main()

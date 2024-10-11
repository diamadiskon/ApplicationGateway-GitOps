#!/bin/bash

# Use environment variables if set, otherwise use default values
# RESOURCE_GROUP="${RESOURCE_GROUP:-YOUR-RG}"
# APPGW_NAME="${APPGW_NAME:-YOUR-AGW-NAME}"
# JSON_FILE="${JSON_FILE:-configuration.json}"

SUBSCRIPTION=$1
echo "[=] Subscription: $SUBSCRIPTION"
RESOURCE_GROUP=$2
echo "[=] Resource Group: $RESOURCE_GROUP"
APPGW_NAME=$3
echo "[=] Application Gateway Name: $APPGW_NAME"
JSON_FILE=$4
echo "[=] JSON Configuration File: $JSON_FILE"

BACKEND_POOLS=$5
echo "[=] ADD Backend Pools: $BACKEND_POOLS"

HTTP_SETTINGS=$6
echo "[=] ADD HTTP Settings: $HTTP_SETTINGS"

HEALTH_PROBES=$7
echo "[=] ADD Health Probes: $HEALTH_PROBES"

URL_PATH_MAPS=$8
echo "[=] ADD URL Path Maps: $URL_PATH_MAPS"

PATH_RULES=$9
echo "[=] ADD Path Rules: $PATH_RULES"

ROUTING_RULES=${10}
echo "[=] ADD Routing Rules: $ROUTING_RULES"

# Check if the right number of arguments are passed
if [ "$#" -ne 10 ]; then
    echo "Usage: $0 SUBSCRIPTION RESOURCE_GROUP APPGW_NAME JSON_FILE BACKEND_POOLS HTTP_SETTINGS HEALTH_PROBES URL_PATH_MAPS PATH_RULES ROUTING_RULES"
    exit 1
fi


# Function to create backend address pools
create_backend_pools() {
    if [ -z "$JSON_FILE" ]; then
        echo "JSON file is not specified."
        exit 1
    fi

    jq -c '.backendAddressPools[]?' "$JSON_FILE" | while read -r pool; do
        NAME=$(echo "$pool" | jq -r .name)
        ADDRESSES_FQDN=$(echo "$pool" | jq -r '.properties.backendAddresses[]?.fqdn')
        echo "$ADDRESSES_FQDN"
        ADDRESSES_IP=$(echo "$pool" | jq -r '.properties.backendAddresses[]?.ipAddress')
        echo "$ADDRESSES_IP"
        if [ -z "$ADDRESSES_IP" ] || [ "$ADDRESSES_IP" = "null" ]; then 
           echo "Trying FQDN addresses..."
           if [ -z "$ADDRESSES_FQDN" ] || [ "$ADDRESSES_FQDN" = "null" ]; then
            echo "Import backendAddressPools without backendAddresses"
            az network application-gateway address-pool create \
            --gateway-name "$APPGW_NAME" \
            --subscription "$SUBSCRIPTION" \
            --resource-group "$RESOURCE_GROUP" \
            --name "$NAME"
            continue
           else 
            echo "Backend address pool with FQDN"
            az network application-gateway address-pool create \
            --gateway-name "$APPGW_NAME" \
            --subscription "$SUBSCRIPTION" \
            --resource-group "$RESOURCE_GROUP" \
            --name "$NAME" \
            --servers "$ADDRESSES_FQDN"
           fi
        else 
            echo "Backend address pool with ipAddress"
            az network application-gateway address-pool create \
            --gateway-name "$APPGW_NAME" \
            --subscription "$SUBSCRIPTION" \
            --resource-group "$RESOURCE_GROUP" \
            --name "$NAME" \
            --servers "$ADDRESSES_IP"
        fi

     done
}

# Function to create HTTP settings
create_http_settings() {
  jq -c '.backendHttpSettingsCollection[]' "$JSON_FILE" | while read -r settings; do
    NAME=$(echo "$settings" | jq -r .name)
    PORT=$(echo "$settings" | jq -r .properties.port)
    PROTOCOL=$(echo "$settings" | jq -r .properties.protocol)
    TIMEOUT=$(echo "$settings" | jq -r .properties.requestTimeout)
    PROBE_NAME=$(echo "$settings" | jq -r .properties.probe.id)
    ADDRESSES_FQDN=$(echo "$settings" | jq -r '.properties.hostName')
    echo "$ADDRESSES_FQDN"
    
    if [ -z "$PORT" ]; then
      echo "Skipping $NAME: Port is not specified."
      continue
    fi
    echo "$PROBE_NAME"
  # Handle cases where PROBE_NAME is "null"
  if [ "$PROBE_NAME" = "null" ]; then
    # If PROBE_NAME is "null", do not include the --probe parameter
    az network application-gateway http-settings create \
      --gateway-name "$APPGW_NAME" \
      --subscription "$SUBSCRIPTION" \
      --resource-group "$RESOURCE_GROUP" \
      --name "$NAME" \
      --port "$PORT" \
      --host-name-from-backend-pool "false" \
      --path "/" \
      --host-name "$ADDRESSES_FQDN" \
      --protocol "$PROTOCOL" \
      --timeout "$TIMEOUT"
  elif [ -n "$PROBE_NAME" ]; then
    # Check if PROBE_NAME is non-empty and not equal to "null"
    az network application-gateway http-settings create \
      --gateway-name "$APPGW_NAME" \
      --subscription "$SUBSCRIPTION" \
      --resource-group "$RESOURCE_GROUP" \
      --name "$NAME" \
      --port "$PORT" \
      --host-name-from-backend-pool "false" \
      --path "/" \
      --host-name "$ADDRESSES_FQDN" \
      --protocol "$PROTOCOL" \
      --timeout "$TIMEOUT" \
      --probe "$PROBE_NAME"
  else
    # Additional handling for empty PROBE_NAME (if needed)
    echo "Skipping $NAME: PROBE_NAME is empty."
  fi
  done
}


# Function to create URL path maps
create_url_path_maps() {
  jq -c '.urlPathMaps[]' "$JSON_FILE" | while read -r urlPathMap; do
    PATH_MAP_NAME=$(echo "$urlPathMap" | jq -r .name)
    NAME=$(echo "$urlPathMap" | jq -r .properties.pathRules[].name)
    ADDRESSES_POOL=$(echo "$urlPathMap" | jq -r .properties.pathRules[].properties.backendAddressPool.id)
    HTTP_SETTINGS=$(echo "$urlPathMap" | jq -r .properties.pathRules[].properties.backendHttpSettings.id)
    DEFAULT_POOL=$(echo "$urlPathMap" | jq -r .properties.defaultBackendAddressPool.id)
    DEFAULT_SETTINGS=$(echo "$urlPathMap" | jq -r .properties.defaultBackendHttpSettings.id)


    echo "$urlPathMap" | jq -r --arg NAME "$PATH_MAP_NAME" '.properties.pathRules[] | .properties.paths[] | "\($NAME): \(.)"' | while read -r line; do
      echo "Processing $line"
      # Extract the actual path
      PATH1111=$(echo "$line" | cut -d ':' -f 2 | xargs)
         echo "$PATH1111"
        # Add your processing logic here
          az network application-gateway url-path-map create \
            --gateway-name "$APPGW_NAME" \
            --name "$NAME" \
            --paths "$PATH1111" \
            --resource-group "$RESOURCE_GROUP" \
            --address-pool "$ADDRESSES_POOL" \
            --default-address-pool "$DEFAULT_POOL" \
            --default-http-settings "$DEFAULT_SETTINGS" \
            --http-settings "$HTTP_SETTINGS" \
            --rule-name "$NAME"

    done
 


  done
}

create_url_path_maps_rules() {
## TODO 
  # Read each PathRoute from the JSON file and process it
  jq -c '.pathRoutes[]' "$JSON_FILE" | while read -r pathRoute; do
    # Extract the URL path map name
    PATH_MAP_NAME=$(echo "$pathRoute" | jq -r '.urlPathMapName.name')

    # Read each path rule
    jq -c '.pathRules[]' <<< "$pathRoute" | while read -r pathRule; do
      # Extract values from the path rule
      ROUTEPATH=$(echo "$pathRule" | jq -r .path)
      NAME=$(echo "$pathRule" | jq -r .name)
      APPGW_RULE_NAME=$(echo "$pathRule" | jq -r .name)
      BACKEND_ID=$(echo "$pathRule" | jq -r '.backendAddressPool.id')
      HTTP_SETTINGS_ID=$(echo "$pathRule" | jq -r '.backendHttpSettings.id')

      # Extract the base names from IDs
      BASENAME_BP=$(basename "$BACKEND_ID")
      BASENAME_HS=$(basename "$HTTP_SETTINGS_ID")

      # Echo extracted values for debugging
      echo "Path: $ROUTEPATH"
      echo "Path Map Name: $APPGW_RULE_NAME"
      echo "Rule Name: $NAME"
      echo "Backend Pool ID Base Name: $BASENAME_BP"
      echo "HTTP Settings ID Base Name: $BASENAME_HS"

      # Run the Azure CLI command for each path rule
      az network application-gateway url-path-map rule create \
        --gateway-name "$APPGW_NAME" \
        --subscription "$SUBSCRIPTION" \
        --resource-group "$RESOURCE_GROUP" \
        --path-map-name "$APPGW_RULE_NAME" \
        --name "$NAME" \
        --paths "$ROUTEPATH" \
        --address-pool "$BASENAME_BP" \
        --http-settings "$BASENAME_HS"
    done

  done

}



# Function to update routing rules
## TODO
update_routing_rules() {
  # Loop through each request routing rule in the JSON file
  jq -c '.requestRoutingRules[]' "$JSON_FILE" | while read -r rule; do
    NAME=$(echo "$rule" | jq -r .name)
    LISTENER_ID=$(echo "$rule" | jq -r .properties.listener.id)
    URL_PATH_MAP_ID=$(echo "$rule" | jq -r .properties.urlPathMap.id)
    PRIORITY=$(echo "$rule" | jq -r .properties.priority)

    if [ "$NAME" == "null" ] || [ "$LISTENER_ID" == "null" ] || [ "$URL_PATH_MAP_ID" == "null" ] || [ "$PRIORITY" == "null" ]; then
      echo "Skipping $NAME: Missing required fields or fields are null."
      continue
    fi

    az network application-gateway routing-rule create \
      --resource-group "$RESOURCE_GROUP" \
      --gateway-name "$APPGW_NAME" \
      --name "$NAME" \
      --listener "test" \
      --address-pool "test" \
      --priority "$PRIORITY" \
      --rule-type "PathBasedRouting"

    echo "Created request routing rule: $NAME"
  done
}

# Function to create health probes
create_probes() {
  jq -c '.probes[]?' "$JSON_FILE" | while read -r probe; do
    NAME=$(echo "$probe" | jq -r .name)
    echo "$NAME"
    PROTOCOL=$(echo "$probe" | jq -r .properties.protocol)
    echo "$PROTOCOL"
    HOST=$(echo "$probe" | jq -r .properties.host)
    echo "$HOST"
    PROBE_PATH=$(echo "$probe" | jq -r .properties.path)
    echo "$PROBE_PATH"
    INTERVAL=$(echo "$probe" | jq -r .properties.interval)
    echo "$INTERVAL"
    TIMEOUT=$(echo "$probe" | jq -r .properties.timeout)
    echo "$TIMEOUT"
    THRESHOLD=$(echo "$probe" | jq -r .properties.unhealthyThreshold)
    echo "$THRESHOLD"

    az network application-gateway probe create \
      --gateway-name "$APPGW_NAME" \
      --subscription "$SUBSCRIPTION" \
      --resource-group "$RESOURCE_GROUP" \
      --name "$NAME" \
      --protocol "$PROTOCOL" \
      --host "$HOST" \
      --path "$PROBE_PATH" \
      --interval "$INTERVAL" \
      --timeout "$TIMEOUT" \
      --threshold "$THRESHOLD" \

    echo "Created probe: $NAME"
  done
}

# Check if jq is installed
if ! command -v jq &> /dev/null; then
  echo "jq is not installed. Please install jq to run this script."
  exit 1
fi

# Check if az is installed
if ! command -v az &> /dev/null; then
  echo "Azure CLI (az) is not installed. Please install Azure CLI to run this script."
  exit 1
fi


# Ensure variables are set
if [ -z "$APPGW_NAME" ] || [ -z "$RESOURCE_GROUP" ] || [ -z "$SUBSCRIPTION" ]; then
    echo "APPGW_NAME and RESOURCE_GROUP and SUBSCRIPTION must be set."
    exit 1
fi



  ##Execute functions

  if [ "$BACKEND_POOLS" = "true" ]; then
    echo "Creating backend pools..."
    create_backend_pools
  fi

  if [ "$HTTP_SETTINGS" = "true" ]; then
    echo "Creating HTTP settings..."
    create_http_settings
  fi

  if [ "$HEALTH_PROBES" = "true"  ]; then
    echo "Creating health probes..."
    create_probes
  fi

  if [ "$URL_PATH_MAPS"  = "true" ]; then
    echo "Creating URL path maps..."
    create_url_path_maps_rules
  fi

  if [ "$PATH_RULES" = "true" ]; then
    echo "Creating Path Rules..."
    create_url_path_maps
  fi

  if [ "$ROUTING_RULES" = "true" ]; then
      echo "Creating Routing Rules..."
      update_routing_rules
  fi





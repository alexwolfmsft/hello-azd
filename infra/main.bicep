targetScope = 'subscription'

// The main bicep module to provision Azure resources.
// For a more complete walkthrough to understand how this file works with azd,
// see https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/make-azd-compatible?pivots=azd-create

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

param storageAccountName string = ''
param appServicePlanName string = ''
param containerAppsEnvName string = ''
param containerAppsAppName string = ''

param serviceName string = 'web'

// Optional parameters to override the default azd resource naming conventions.
// Add the following to main.parameters.json to provide values:
// "resourceGroupName": {
//      "value": "myGroupName"
// }
param resourceGroupName string = ''

@description('Id of the user or app to assign application roles')
param principalId string = ''

var abbrs = loadJsonContent('./abbreviations.json')

// tags that should be applied to all resources.
var tags = {
  // Tag all resources with the environment name.
  'azd-env-name': environmentName
}

// Generate a unique token to be used in naming resources.
// Remove linter suppression after using.
#disable-next-line no-unused-vars
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))

// Name of the service defined in azure.yaml
// A tag named azd-service-name with this value should be applied to the service host resource, such as:
//   Microsoft.Web/sites for appservice, function
// Example usage:
//   tags: union(tags, { 'azd-service-name': apiServiceName })
#disable-next-line no-unused-vars
var apiServiceName = 'python-api'

// Organize resources in a resource group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

// Add resources to be provisioned below.
// A full example that leverages azd bicep modules can be seen in the todo-python-mongo template:
// https://github.com/Azure-Samples/todo-python-mongo/tree/main/infra

module identity './app/user-assigned-identity.bicep' = {
  name: 'identity'
  scope: rg
  params: {
    name: 'hello-azd-identity'
  }
}

module cosmos 'app/cosmos.bicep' = {
  name: 'cosmos'
  scope: rg
  params: {
    principalId: principalId
    identityId: identity.outputs.principalId
  }
}

// Backing storage for Azure functions backend API
module storage './core/storage/storage-account.bicep' = {
  name: 'storage'
  scope: rg
  params: {
    name: !empty(storageAccountName) ? storageAccountName : '${abbrs.storageStorageAccounts}${resourceToken}'
    location: location
    tags: tags
  }
}

// Assign storage blob data contributor to the user
module userAssignStorage './app/role-assignment.bicep' = {
  name: 'assignStorage'
  scope: rg
  params: {
    principalId: principalId
    roleDefinitionID: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  }
}

// Assign storage blob data contributor to the app
module appAssignStorage './app/role-assignment.bicep' = {
  name: 'appAssignStorage'
  scope: rg
  params: {
    principalId: identity.outputs.principalId
    roleDefinitionID: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  }
}

module appService 'core/host/appservice.bicep' = {
  name: 'appService'
  scope: rg
  params: {
    name: !empty(appServicePlanName) ? appServicePlanName : '${abbrs.webSitesAppService}${resourceToken}'
    location: location
    tags: union(tags, { 'azd-service-name': 'web' })
    appServicePlanId: appServicePlan.outputs.id
    runtimeName: 'dotnet'
    runtimeVersion: 'v8.0'
    userAssignedIdentityId: identity.outputs.resourceId
    storageEndpoint: storage.outputs.primaryEndpoints.blob
    cosmosDbEndpoint: cosmos.outputs.endpoint
    userAssignedIdentityPrincipalId: identity.outputs.principalId
  }
}

// Create an App Service Plan to group applications under the same payment plan and SKU
module appServicePlan './core/host/appserviceplan.bicep' = {
  name: 'appserviceplan'
  scope: rg
  params: {
    name: !empty(appServicePlanName) ? appServicePlanName : '${abbrs.webServerFarms}${resourceToken}'
    location: location
    tags: tags
    sku: {
      name: 'S1'
    }
  }
}

// module web './app/container-app.bicep' = {
//   name: serviceName
//   scope: rg
//   params: {
//     envName: !empty(containerAppsEnvName) ? containerAppsEnvName : '${abbrs.appContainerApps}env-${resourceToken}'
//     appName: !empty(containerAppsAppName) ? containerAppsAppName : '${abbrs.appContainerApps}${resourceToken}'
//     databaseAccountEndpoint: cosmos.outputs.endpoint
//     storageAccountEndpoint: storage.outputs.primaryEndpoints.blob
//     userAssignedManagedIdentity: {
//       resourceId: identity.outputs.resourceId
//       clientId: identity.outputs.clientId
//     }
//     location: location
//     tags: tags
//     serviceTag: serviceName
//   }
// }

// Add outputs from the deployment here, if needed.
//
// This allows the outputs to be referenced by other bicep deployments in the deployment pipeline,
// or by the local machine as a way to reference created resources in Azure for local development.
// Secrets should not be added here.
//
// Outputs are automatically saved in the local azd environment .env file.
// To see these outputs, run `azd env get-values`,  or `azd env get-values --output json` for json output.
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId

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
param containerRegistryName string = ''

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

// Organize resources in a resource group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

// Add resources to be provisioned below.
// A full example that leverages azd bicep modules can be seen in the todo-python-mongo template:
// https://github.com/Azure-Samples/todo-python-mongo/tree/main/infra

// Create a user assigned identity
module identity './app/user-assigned-identity.bicep' = {
  name: 'identity'
  scope: rg
  params: {
    name: 'hello-azd-identity'
  }
}

// Create a cosmos db account
module cosmos 'app/cosmos.bicep' = {
  name: 'cosmos'
  scope: rg
  params: {
    userPrincipalId: principalId
    managedIdentityId: identity.outputs.principalId
  }
}

// Create a storage account
module storage './core/storage/storage-account.bicep' = {
  name: 'storage'
  scope: rg
  params: {
    name: !empty(storageAccountName) ? storageAccountName : '${abbrs.storageStorageAccounts}${resourceToken}'
    location: location
    tags: tags
    containers: [
      {
        name: 'attachments'
      }
    ]
  }
}

// Assign storage blob data contributor to the user
module userAssignStorage './app/role-assignment.bicep' = {
  name: 'assignStorage'
  scope: rg
  params: {
    principalId: principalId
    roleDefinitionID: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // built-in role definition id for storage blob data contributor
    principalType: 'User'
  }
}

// Assign storage blob data contributor to the app
module appAssignStorage './app/role-assignment.bicep' = {
  name: 'appAssignStorage'
  scope: rg
  params: {
    principalId: identity.outputs.principalId
    roleDefinitionID: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
    principalType: 'ServicePrincipal'
  }
}

// // Create the app service
// module appService 'core/host/appservice.bicep' = {
//   name: 'appService'
//   scope: rg
//   params: {
//     name: !empty(appServicePlanName) ? appServicePlanName : '${abbrs.webSitesAppService}${resourceToken}'
//     location: location
//     tags: union(tags, { 'azd-service-name': 'web' })
//     appServicePlanId: appServicePlan.outputs.id
//     runtimeName: 'dotnet'
//     runtimeVersion: '8.0'
//     userAssignedIdentityId: identity.outputs.resourceId
//     storageEndpoint: storage.outputs.primaryEndpoints.blob
//     cosmosDbEndpoint: cosmos.outputs.endpoint
//     userAssignedIdentityClientId: identity.outputs.clientId
//   }
// }

// // Create an App Service Plan to group applications under the same payment plan and SKU
// module appServicePlan './core/host/appserviceplan.bicep' = {
//   name: 'appserviceplan'
//   scope: rg
//   params: {
//     name: !empty(appServicePlanName) ? appServicePlanName : '${abbrs.webServerFarms}${resourceToken}'
//     location: location
//     tags: tags
//     sku: {
//       name: 'S1'
//     }
//   }
// }

// module containerRegistry 'core/host/container-registry.bicep' = {
//   name: 'container-registry'
//   scope: rg
//   params: {
//     name: !empty(storageAccountName) ? storageAccountName : '${abbrs.containerRegistryRegistries}${resourceToken}'
//     location: location
//     tags: tags
//     adminUserEnabled: false
//     anonymousPullEnabled: true
//     publicNetworkAccess: 'Enabled'
//     sku: {
//       name: 'Standard'
//     }
//   }
// }

module web 'app/web.bicep' = {
  name: serviceName
  scope: rg
  params: {
    parentEnvironmentName: containerApps.outputs.environmentName
    appName: !empty(containerAppsAppName) ? containerAppsAppName : '${abbrs.appContainerApps}${resourceToken}'
    databaseAccountEndpoint: cosmos.outputs.endpoint
    userAssignedManagedIdentity: {
      resourceId: identity.outputs.resourceId
      clientId: identity.outputs.clientId
    }
    location: location
    tags: tags
    serviceTag: serviceName
  }
}

// Container apps host (including container registry)
module containerApps './core/host/container-apps.bicep' = {
  name: 'container-apps'
  scope: rg
  params: {
    name: 'app'
    containerAppsEnvironmentName: !empty(containerAppsEnvName) ? containerAppsEnvName : '${abbrs.appManagedEnvironments}${resourceToken}'
    containerRegistryName: !empty(containerRegistryName) ? containerRegistryName : '${abbrs.containerRegistryRegistries}${resourceToken}'
    containerRegistryAdminUserEnabled: true
    location: location
  }
}

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
// Container outputs
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = containerApps.outputs.registryLoginServer
output AZURE_CONTAINER_REGISTRY_NAME string = containerApps.outputs.registryName

// // Application outputs
// output AZURE_CONTAINER_APP_ENDPOINT string = web.outputs.endpoint
// output AZURE_CONTAINER_ENVIRONMENT_NAME string = web.outputs.envName

// Identity outputs
output AZURE_USER_ASSIGNED_IDENTITY_NAME string = identity.outputs.name

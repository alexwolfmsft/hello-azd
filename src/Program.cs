using MudBlazor.Services;
using HelloAZD.Components;
using HelloAZD.Services;
using Microsoft.Azure.Cosmos;
using Azure.Identity;
using Azure.ResourceManager;
using Microsoft.Extensions.Azure;

var builder = WebApplication.CreateBuilder(args);

// Add MudBlazor services
builder.Services.AddMudServices();

var identity = new DefaultAzureCredential(new DefaultAzureCredentialOptions { ManagedIdentityClientId = builder.Configuration["AZURE_CLIENT_ID"] });

builder.Services.AddAzureClients(clientBuilder =>
{
    // Register clients for each service
    clientBuilder.AddBlobServiceClient(new Uri(builder.Configuration["STORAGE_URL"]));
    clientBuilder.AddClient<CosmosClient, CosmosClientOptions>((options) =>
    {
    CosmosClient client = new(
        accountEndpoint: builder.Configuration["AZURE_COSMOS_DB_NOSQL_ENDPOINT"]!,
        tokenCredential: identity
        );
        return client;
    });
    clientBuilder.UseCredential(identity);
});

// Register ArmClient and SubscriptionService
builder.Services.AddSingleton(new ArmClient(identity));
builder.Services.AddScoped<SubscriptionService>();

// Add services to the container.
builder.Services.AddRazorComponents()
    .AddInteractiveServerComponents();

var app = builder.Build();


// Configure the HTTP request pipeline.
if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error", createScopeForErrors: true);
    // The default HSTS value is 30 days. You may want to change this for production scenarios, see https://aka.ms/aspnetcore-hsts.
    app.UseHsts();
}

app.UseHttpsRedirection();

app.UseStaticFiles();
app.UseAntiforgery();

app.MapRazorComponents<App>()
    .AddInteractiveServerRenderMode();

app.Run();

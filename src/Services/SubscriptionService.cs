using Azure.Core;
using Azure.ResourceManager;
using Azure.ResourceManager.Resources;

namespace HelloAZD.Services;

public class SubscriptionService
{
    private readonly ArmClient _armClient;

    public SubscriptionService(ArmClient armClient)
    {
        _armClient = armClient;
    }

    public async Task<List<SubscriptionData>> GetSubscriptionsAsync()
    {
        var subscriptions = new List<SubscriptionData>();
        
        await foreach (var subscription in _armClient.GetSubscriptions())
        {
            subscriptions.Add(new SubscriptionData
            {
                SubscriptionId = subscription.Data.SubscriptionId,
                DisplayName = subscription.Data.DisplayName,
                State = subscription.Data.State?.ToString() ?? "Unknown",
                TenantId = subscription.Data.TenantId?.ToString() ?? "Unknown"
            });
        }

        return subscriptions;
    }
}

public class SubscriptionData
{
    public string SubscriptionId { get; set; } = string.Empty;
    public string DisplayName { get; set; } = string.Empty;
    public string State { get; set; } = string.Empty;
    public string TenantId { get; set; } = string.Empty;
}

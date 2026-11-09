using System;

namespace SecuredClient.Provider
{
    public abstract class TestServiceProvider : ServiceProvider
    {
        public override Uri Endpoint => new Uri("https://stest.bankconnect.dk/2019/04/04/services/CorporateService/");
    }
}
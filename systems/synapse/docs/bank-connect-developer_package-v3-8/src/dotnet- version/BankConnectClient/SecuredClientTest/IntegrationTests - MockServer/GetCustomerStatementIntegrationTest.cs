using System;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using SecuredClient.Client;

namespace SecuredClientTest.IntegrationTests
{
    [TestClass]
    public class GetCustomerStatementIntegrationTest : BankConnectIntegrationTest
    {
        [TestMethod]
        [DeploymentItem("Resources/erp.p12")]
        public void InvokeGetCustomerStatement()
        {
            SetupCertificateStoreWithClientCredentials();
            var clientFactory = new SecuredCorporateServiceClientFactory();
            var client = clientFactory.CreateClient(ServiceProvider.Endpoint);

            var request = new getCustomerStatement();

            var technicalAddress = new technicalAddress();
            var serviceHeader = RequestBuilder.BuildServiceHeader();
            var response = client.getCustomerStatement(ref technicalAddress, ref serviceHeader, request);

            Console.WriteLine(response.corporateMessage);

        }
    }
}
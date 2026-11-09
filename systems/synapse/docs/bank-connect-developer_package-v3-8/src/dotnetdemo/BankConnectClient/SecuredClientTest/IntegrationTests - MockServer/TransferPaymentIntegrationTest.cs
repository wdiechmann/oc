using System;
using System.Text;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using SecuredClient.Client;

namespace SecuredClientTest.IntegrationTests
{
    [TestClass]
    public class TransferPaymentIntegrationTest : BankConnectIntegrationTest
    {
        //At the moment, the mockServer doesn't sign the body of the transferPayment response
        //and this test will fail when validating the business signature.
        //Until the mockServer is fixed, the following temporary work-around can be to applied:
        //When calling transferPayment on the mockServer, skip the validation by commenting out
        //ValidateBusinessSignature(response) in SecurityServiceImpl.cs line 45
        //NB! This only applies to the mockServer and only when calling transferPayment
        [TestMethod]
        [DeploymentItem("Resources/erp.p12")]
        public void TransferPayment()
        {
            SetupCertificateStoreWithClientCredentials();
            var clientFactory = new SecuredCorporateServiceClientFactory();
            var client = clientFactory.CreateClient(ServiceProvider.Endpoint);
            var request = new transferPayment();
            var paymentMessage = new paymentMessage();
            paymentMessage.content = Encoding.UTF8.GetBytes("<xml></xml>");
            paymentMessage.format = "format";
            paymentMessage.mimeType = "text/xml";
            paymentMessage.compressed = "1";

            request.paymentMessage = paymentMessage;

            var technicalAddress = new technicalAddress();
            var serviceHeader = RequestBuilder.BuildServiceHeader();
            var response = client.transferPayments(ref technicalAddress, ref serviceHeader, request);

            Console.WriteLine(response.paymentResponse);

        }

    }
}

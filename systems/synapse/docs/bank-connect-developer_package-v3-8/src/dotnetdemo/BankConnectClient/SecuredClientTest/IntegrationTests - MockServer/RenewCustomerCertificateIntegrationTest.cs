using System;
using System.Text;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using SecuredClient.Client;
using SecuredClient.Request;

namespace SecuredClientTest.IntegrationTests
{
    [TestClass]
    public class RenewCustomerCertificateIntegrationTest : BankConnectIntegrationTest
    {
        [TestMethod]
        [DeploymentItem("Resources/erp.p12")]
        public void Renew()
        {
            SetupCertificateStoreWithClientCredentials();

            var certificateRequestGenerator = new CertificateRequestGenerator("112233445566778899"); 
            var pkcs10Bytes = certificateRequestGenerator.GetPkcs10Bytes();

            var clientFactory = new SecuredCorporateServiceClientFactory();

            var client = clientFactory.CreateClient(ServiceProvider.Endpoint);

            var request = new renewCustomerCertificate();
            request.certificateRequestMessage = new certificateRequestMessage {certificateRequest = pkcs10Bytes};

            var technicalAddress = new technicalAddress();
            var serviceHeader = RequestBuilder.BuildServiceHeader();

            
            var response = client.renewCustomerCertificate(ref technicalAddress, ref serviceHeader, request);

            Console.WriteLine(response.corporateMessage.description);

            var pemBlock = Encoding.UTF8.GetString(response.corporateMessage.content);


            ActivateServiceAgreementIntegrationTest.ReceiveAndValidateCertifices(pemBlock, certificateRequestGenerator);

        }
    }
}

using System.Text;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using SecuredClient.Client;
using SecuredClient.Crypto;
using SecuredClient.Request;

namespace SecuredClientTest.IntegrationTests
{
    [TestClass]
    public class ActivateServiceAgreementIntegrationTest : BankConnectIntegrationTest
    {
        [TestMethod]
        public void ActivateServiceAgreement()
        {
            SetupCertificateStore(); //No client credentials available yet.

            const string activationCode = "5647382910TGRFDE";
            const string functionIdentifier = "112233445566778899";
            var certificateRequestGenerator = new CertificateRequestGenerator(functionIdentifier, activationCode);
            var pkcs10Bytes = certificateRequestGenerator.GetPkcs10Bytes();

            var clientFactory = new SecuredCorporateServiceClientFactory();
            var client = clientFactory.CreateClient(ServiceProvider.Endpoint);

            var request = new activateServiceAgreement();
            var activationHeader = RequestBuilder.BuildActivationHeader();
            activationHeader.functionIdentification = functionIdentifier;
            var activationAgreement = new activationAgreement();
            activationAgreement.activationCode = Encoding.UTF8.GetBytes(activationCode);
            activationAgreement.certificateRequest = pkcs10Bytes;
            request.activationAgreement = activationAgreement;

            var technicalAddress = new technicalAddress();
            var response = client.activateServiceAgreement(ref technicalAddress, ref activationHeader, request);

            var pemBlock = Encoding.UTF8.GetString(response.corporateMessage.content);

            ReceiveAndValidateCertifices(pemBlock, certificateRequestGenerator);
        }

        public static void ReceiveAndValidateCertifices(string pemBlock, CertificateRequestGenerator certificateRequestGenerator)
        {
            var reader = new PemBlockReader(pemBlock);

            var certificates = reader.ReadCertificates();

            new CertificateChainValidator(CertificateStore.Instance.TrustedCaCertificates).AssertValid(certificates);

        }
    }
}

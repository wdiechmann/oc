using System;
using System.Collections.Generic;
using System.Security.Cryptography.X509Certificates;
using System.ServiceModel;
using System.Text;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using SecuredClient.Client;
using SecuredClient.Crypto;
using SecuredClient.Provider;

namespace SecuredClientTest.IntegrationTests
{
    [TestClass]
    public class GetBankCertificateTest
    {
        [TestMethod]
        public void GetBankCertificate()
        {
            var provider = new BankdataSystemtestServiceProvider();
            
            CertificateStore.Instance.AddTrustedCaCertificate(provider.RootCaCertificate);
            var uri = provider.Endpoint;

            var client = new SecuredCorporateServiceClient(new EndpointAddress(uri));

            var technicalAddress = new technicalAddress();
            var activationHeader = BuildActivationHeader(provider);
            var request = new getBankCertificate();

            var response = client.getBankCertificate(ref technicalAddress, ref activationHeader, request);

            var chain = ReadCertificateChain(response);

            VerifyCertificateChain(chain);
        }

        private static ActivationHeader BuildActivationHeader(ServiceProvider provider)
        {
            var activationHeader = new ActivationHeader();
            activationHeader.createDateTime = DateTime.Now;
            activationHeader.endToEndMessageId = Guid.NewGuid().ToString();
            activationHeader.functionIdentification = "1234";

            var erpInformation = new erpInformation();
            erpInformation.erpsystem = "erp";
            erpInformation.erpversion = "1.0";
            activationHeader.erpInformation = erpInformation;

            var organisationIdentification = new organisationIdentification();
            organisationIdentification.isoCountryCode = "DK";
            organisationIdentification.mainRegistrationNumber = provider.RegistrationNumber;
            activationHeader.organisationIdentification = organisationIdentification;
            return activationHeader;
        }

        private static IList<X509Certificate2> ReadCertificateChain(getBankCertificateResponse response)
        {
            var block = Encoding.UTF8.GetString(response.corporateMessage.content);
            var reader = new PemBlockReader(block);

            var list = reader.ReadCertificates();

            var count = 0;
            foreach (var certificate in list)
            {
                Console.WriteLine("Cert nr " + ++count + ", Subject: " + certificate.SubjectName.Name + ", Issuer: " + certificate.IssuerName.Name);
            }
            return list;
        }


        private static void VerifyCertificateChain(IList<X509Certificate2> list)
        {
            new CertificateChainValidator(CertificateStore.Instance.TrustedCaCertificates).AssertValid(list);
        }

        [TestMethod]
        public void ShowRoot()
        {
            var provider = new BankdataSystemtestServiceProvider();

            Console.WriteLine(provider.RootCaCertificate);

            var other = new SecuredClient.Provider.BankdataSystemtestServiceProvider();

            Console.WriteLine(other.RootCaCertificate);

        }
    }
}

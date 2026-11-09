using Microsoft.VisualStudio.TestTools.UnitTesting;
using SecuredClient.Provider;

namespace SecuredClientTest.Provider
{
    [TestClass]
    public class ServiceProviderTest
    {
        [TestMethod]
        public void TestCertificates()
        {
            AssertSubject("CN=BEC ROOT CA, O=BEC - Bankernes EDB Central, OU=BECSSLCERTS, C=DK", new BECProductionServiceProvider());
            AssertSubject("CN=BEC Root CA - Test, O=BEC - Bankernes EDB Central, OU=BECSSLCERTS, C=DK", new BECSystemtestServiceProvider());
            AssertSubject("C=DK, O=Bankdata, OU=SIK, L=Erritsoe Fredericia, CN=BD BankConnect Primary CA", new BankdataProductionServiceProvider());
            AssertSubject("C=DK, O=Bankdata, OU=VBF, L=Erritsoe Fredericia, CN=BD BankConnect Primary CA Test", new BankdataSystemtestServiceProvider());
            AssertSubject("CN=SDC Bank Connect Primary CA, OU=eBank, O=Skandinavisk Data Center AS, L=Ballerup, C=DK", new SDCProductionServiceProvider());
            AssertSubject("CN=SDC Bank Connect Primary CA Test, OU=eBank, O=Skandinavisk Data Center AS, L=Ballerup, C=DK", new SDCSystemtestServiceProvider());
        }

        private static void AssertSubject(string subject, ServiceProvider provider)
        {
            Assert.AreEqual(subject, provider.RootCaCertificate.SubjectName.Name);
        }
    }
}

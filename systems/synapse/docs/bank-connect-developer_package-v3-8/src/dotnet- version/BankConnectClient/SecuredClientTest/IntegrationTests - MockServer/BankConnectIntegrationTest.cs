using SecuredClient.Crypto;

namespace SecuredClientTest.IntegrationTests
{
    public class BankConnectIntegrationTest
    {
        protected DevServiceProvider ServiceProvider;

        protected void SetupCertificateStore()
        {
            ServiceProvider = new DevServiceProvider();
            CertificateStore.Instance.ServiceCertificate = ServiceProvider.BankCertificate;
            CertificateStore.Instance.AddTrustedCaCertificate(ServiceProvider.RootCaCertificate);
            CertificateStore.Instance.AddTrustedCaCertificate(ServiceProvider.IntermediateCertificate);
        }

        protected void SetupCertificateStoreWithClientCredentials()
        {
            SetupCertificateStore();
            CertificateStore.Instance.ClientCertificate = ServiceProvider.ClientCertificate;
        }

    }
}

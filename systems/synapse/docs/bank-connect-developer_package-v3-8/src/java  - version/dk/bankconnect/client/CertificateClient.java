package dk.bankconnect.client;

import java.io.ByteArrayInputStream;
import java.security.cert.Certificate;
import java.security.cert.CertificateFactory;
import java.util.HashMap;
import java.util.Map;

import org.apache.cxf.interceptor.LoggingInInterceptor;
import org.apache.cxf.interceptor.LoggingOutInterceptor;
import org.apache.cxf.jaxws.JaxWsProxyFactoryBean;
import org.apache.cxf.ws.security.wss4j.DefaultCryptoCoverageChecker;
import org.apache.cxf.ws.security.wss4j.WSS4JInInterceptor;
import org.apache.cxf.ws.security.wss4j.WSS4JOutInterceptor;

import dk.bankconnect.certificate.CertificateService;

/**
 * The Class CertificateClient.
 */
public class CertificateClient {
    private final static String WSSE_NS = "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd";
    private final static String WSU_NS = "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd";

    /**
     * The main method.
     *
     * @param args the arguments
     */
    public static void main(String[] args) {
        JaxWsProxyFactoryBean factory = new JaxWsProxyFactoryBean();
        
        factory.setAddress("http://localhost:9000/cert");
        factory.setServiceClass(CertificateService.class);
        setInterceptors(factory);
        CertificateService client = (CertificateService) factory.create();
        
        try {
            CertificateFactory certFactory = CertificateFactory.getInstance("X.509");
            //byte[] certBytes= client.getCertificateFromKeystore(null,"bankconnect");
            byte[] certBytes= client.getCertificate("erp-xyz");
            Certificate cert=certFactory.generateCertificate(new ByteArrayInputStream(certBytes));
            System.out.println(cert);
        } catch (Exception e) {
            System.err.println(e);
        }
    }
    
    /**
     * Set the interceptors on the client.
     * @param factory
     */
    private static void setInterceptors(JaxWsProxyFactoryBean factory) {
        Map<String, Object> outProps = new HashMap<String, Object>();
        outProps.put("action", "Signature Encrypt");
        outProps.put("passwordCallbackClass", "dk.bd.bankconnect.client.PasswordCallback");
        outProps.put("user", "erp-xyz");
        outProps.put("encryptionUser", "bankconnect");
        outProps.put("encryptionPropFile", "client.properties");
        outProps.put("encryptionKeyIdentifier", "IssuerSerial");
/*        outProps.put("encryptionParts",
                     "{Element}{" + WSSE_NS + "}UsernameToken;"
                     + "{Content}{http://schemas.xmlsoap.org/soap/envelope/}Body");
  */      
        outProps.put("signaturePropFile", "client.properties");
        outProps.put("signatureKeyIdentifier", "DirectReference");
/*        String s="{Element}{http://schemas.xmlsoap.org/soap/envelope/}Body;"
                + "{}{http://www.w3.org/2005/08/addressing}ReplyTo;";
        outProps.put("signatureParts",s);
*/
        
        outProps.put("encryptionKeyTransportAlgorithm", 
                     "http://www.w3.org/2001/04/xmlenc#rsa-oaep-mgf1p");
        outProps.put("signatureAlgorithm", "http://www.w3.org/2000/09/xmldsig#rsa-sha1");


        Map<String, Object> inProps = new HashMap<String, Object>();
        inProps.put("action", "Signature Encrypt");
        inProps.put("passwordCallbackClass", "dk.bd.bankconnect.client.PasswordCallback");
        inProps.put("decryptionPropFile", "client.properties");
        inProps.put("encryptionKeyIdentifier", "IssuerSerial");

        inProps.put("signaturePropFile", "client.properties");
        inProps.put("signatureKeyIdentifier", "DirectReference");

        inProps.put("encryptionKeyTransportAlgorithm", 
                     "http://www.w3.org/2001/04/xmlenc#rsa-oaep-mgf1p");
        inProps.put("signatureAlgorithm", "http://www.w3.org/2000/09/xmldsig#rsa-sha1");

        
        // Check to make sure that the SOAP Body and Timestamp were signed,
        // and that the SOAP Body was encrypted
        DefaultCryptoCoverageChecker coverageChecker = new DefaultCryptoCoverageChecker();
        coverageChecker.setSignBody(true);
        coverageChecker.setSignTimestamp(true);
        coverageChecker.setEncryptBody(true);
        
        factory.getInInterceptors().add(coverageChecker);
        factory.getInInterceptors().add(new LoggingInInterceptor());
        factory.getInInterceptors().add(new WSS4JInInterceptor(inProps));
        factory.getOutInterceptors().add(new LoggingOutInterceptor());
        factory.getOutInterceptors().add(new WSS4JOutInterceptor(outProps));
    }

}

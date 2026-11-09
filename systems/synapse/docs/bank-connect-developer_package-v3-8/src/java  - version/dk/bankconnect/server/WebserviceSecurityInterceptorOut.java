package dk.bankconnect.server;

import java.io.StringReader;
import java.io.StringWriter;
import java.security.Key;
import java.security.cert.X509Certificate;
import java.util.Properties;

import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;
import javax.xml.transform.Transformer;
import javax.xml.transform.TransformerFactory;
import javax.xml.transform.dom.DOMSource;
import javax.xml.transform.stream.StreamResult;

import org.apache.cxf.binding.soap.SoapFault;
import org.apache.log4j.Logger;
import org.springframework.core.io.support.PropertiesLoaderUtils;
import org.w3c.dom.Document;
import org.xml.sax.InputSource;

import dk.bankconnect.certificate.CertificateService;
import dk.bankconnect.certificate.CertificateServiceImpl;
import dk.bankconnect.security.MessageChangeInterceptor;
import dk.bankconnect.security.SecurityException;
import dk.bankconnect.security.SecurityServiceImpl;
import dk.bankconnect.server.config.Constants;

/**
 * The WebserviceSecurityInterceptorOut class extends the
 * MessageChangeInterceptor class.
 */
public class WebserviceSecurityInterceptorOut extends MessageChangeInterceptor {

    /**
     * Get the logger object from this class.
     */
    @Override
    protected Logger getLogger() {
        return Logger.getLogger(this.getClass());
    }

    /**
     * Returns the out bound message with security.
     * 
     * @param currentEnvelope
     * @param addSecurity
     *            If true security will be added to the message, otherwise false
     * @throws Exception
     * @see Exception
     * @return The out bound message with security
     */
    @Override
    protected Document changeOutboundMessage(Document currentEnvelope, Boolean addSecurity) throws SecurityException {
        Document securedMessage = null;
        if (addSecurity) {
            getLogger().debug(this.getClass().getName() + " has been invoked");
            try {
                CertificateService csi = new CertificateServiceImpl();
                SecurityServiceImpl si = new SecurityServiceImpl();
                Properties properties = PropertiesLoaderUtils.loadAllProperties(Constants.PROPERTY_FILE);
                String signingCertificate = properties
                        .getProperty("dk.bankconnect.security.bankconnectcrypto.signing.certificate");
                String signingKey = properties.getProperty("dk.bankconnect.security.bankconnectcrypto.private.key");

                X509Certificate signCert = csi.getCertificateFromKeystore(null, signingCertificate);
                Key signKey = csi.getKeyFromKeystore(null, signingKey);
                if (encryptionCertificate == null) {
                    String encryptionKey = properties
                            .getProperty("dk.bankconnect.security.bankconnectcrypto.decryption.certificate");
                    encryptionCertificate = csi.getCertificateFromKeystore(null, encryptionKey).getEncoded();
                }
                securedMessage = si.wrapServerSoapMessage(currentEnvelope, signCert.getEncoded(), signKey.getEncoded(),
                        encryptionCertificate);
            } catch (SoapFault e) {
                throw e;
            } catch (Exception e) {
                SecurityException securityException = new SecurityException(e);
                throw securityException.getAsSoapFault();
            }
        }
        return securedMessage;
    }

    @Override
    protected String changeInboundMessage(String currentEnvelope) {
        String outboundEnevelope = null;

        DocumentBuilderFactory domFactory = DocumentBuilderFactory.newInstance();
        domFactory.setNamespaceAware(true);
        DocumentBuilder domBuilder;
        try {
            domBuilder = domFactory.newDocumentBuilder();
            Document xmlDoc = domBuilder.parse(new InputSource(new StringReader(currentEnvelope)));
            Document outboundMessage = changeOutboundMessage(xmlDoc, true);
            StringWriter writer = new StringWriter();
            DOMSource source = new DOMSource(xmlDoc.getDocumentElement());
            Transformer transformer = TransformerFactory.newInstance().newTransformer();
            transformer.transform(source, new StreamResult(writer));
            outboundEnevelope = writer.toString();
        } catch (Exception e) {
            SecurityException se = new SecurityException(e);
            throw se.getAsSoapFault();
        }
        return outboundEnevelope;
    }
}

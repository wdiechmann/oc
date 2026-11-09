package dk.bankconnect.security;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.security.Key;
import java.security.cert.CertificateEncodingException;
import java.security.cert.X509Certificate;
import java.util.Set;

import javax.xml.namespace.QName;
import javax.xml.parsers.DocumentBuilderFactory;
import javax.xml.transform.Transformer;
import javax.xml.transform.TransformerFactory;
import javax.xml.transform.dom.DOMSource;
import javax.xml.transform.stream.StreamResult;

import org.apache.commons.io.IOUtils;
import org.apache.cxf.binding.soap.SoapFault;
import org.apache.cxf.binding.soap.interceptor.SoapPreProtocolOutInterceptor;
import org.apache.cxf.io.CachedOutputStream;
import org.apache.cxf.message.Message;
import org.apache.cxf.phase.AbstractPhaseInterceptor;
import org.apache.cxf.phase.Phase;
import org.apache.log4j.Logger;
import org.w3c.dom.Document;

import dk.bankconnect.BankConnectConstants;

/**
 * The MessageChangeInterceptor class.
 * 
 */
public abstract class MessageChangeInterceptor extends AbstractPhaseInterceptor<Message> {
    protected byte[] encryptionCertificate;
    protected byte[] signingCertificate;
    protected byte[] signingKey;

    /**
     * Constructor.
     */
    public MessageChangeInterceptor() {
        super(Phase.PRE_STREAM);
        addBefore(SoapPreProtocolOutInterceptor.class.getName());
    }

    protected abstract Logger getLogger();

    protected abstract Document changeOutboundMessage(Document doc, Boolean addSecurity) throws SecurityException;

    protected abstract String changeInboundMessage(String currentEnvelope);

    /**
     * This method is responsible for message handling. I.e. determines if the
     * message is inbound / outbound, adds security and flushes the message.
     * 
     * @param message
     *            The message to handle
     */
    public void handleMessage(Message message) {
        boolean isOutbound = false;
        isOutbound = message == message.getExchange().getOutMessage()
                || message == message.getExchange().getOutFaultMessage();

        if (isOutbound) {
            OutputStream os = message.getContent(OutputStream.class);
            CachedStream cs = new CachedStream();
            message.setContent(OutputStream.class, cs);
            message.getInterceptorChain().doIntercept(message);
            try {
                cs.flush();
                IOUtils.closeQuietly(cs);
                CachedOutputStream csnew = (CachedOutputStream) message.getContent(OutputStream.class);
                DocumentBuilderFactory documentBuilderFactory = DocumentBuilderFactory.newInstance();
                documentBuilderFactory.setNamespaceAware(true);
                Document doc = documentBuilderFactory.newDocumentBuilder().parse(csnew.getInputStream());
                csnew.flush();
                IOUtils.closeQuietly(csnew);

                setupMessageSecurity(message);
                Boolean addSecurity = (Boolean) message.getExchange().get("bankconnect.security");
                Document res = changeOutboundMessage(doc, addSecurity);
                if (res != null) {
                    if (getLogger().isDebugEnabled()) {
                        getLogger().debug("Outbound message has been changed.");
                    }
                }
                res = res != null ? res : doc;

                /*
                 * InputStream replaceInStream = IOUtils.toInputStream(res,
                 * "UTF-8");
                 */
                TransformerFactory tf = TransformerFactory.newInstance();
                Transformer trans = tf.newTransformer();

                trans.transform(new DOMSource(doc), new StreamResult(os));

                /*
                 * IOUtils.copy(replaceInStream, os); replaceInStream.close();
                 * IOUtils.closeQuietly(replaceInStream);
                 */
                os.flush();
                message.setContent(OutputStream.class, os);
                IOUtils.closeQuietly(os);

            } catch (SoapFault e) {
                throw e;
            } catch (Exception e) {
                SecurityException se = new SecurityException(e);
                se.setErrorcode(BankConnectConstants.VALIDATION_ERROR);
                throw se.getAsSoapFault();
            } 
        } else {
            try {
                InputStream is = message.getContent(InputStream.class);
                String currentEnvelopeMessage = IOUtils.toString(is, "UTF-8");
                IOUtils.closeQuietly(is);

                if (getLogger().isDebugEnabled()) {
                    getLogger().debug("Inbound message: " + currentEnvelopeMessage);
                }

                String res = changeInboundMessage(currentEnvelopeMessage);
                if (res != null) {
                    if (getLogger().isDebugEnabled()) {
                        getLogger().debug("Inbound message has been changed: " + res);
                    }
                }
                res = res != null ? res : currentEnvelopeMessage;

                is = IOUtils.toInputStream(res, "UTF-8");
                message.setContent(InputStream.class, is);
                IOUtils.closeQuietly(is);

            } catch (SoapFault e) {
                throw e;
            } catch (Exception e) {
                SecurityException se = new SecurityException(e);
                se.setErrorcode(BankConnectConstants.VALIDATION_ERROR);
                throw se.getAsSoapFault();
            } 
        }
    }

    /**
     * Sets up message security - signing the message with an X509 formated
     * certificate.
     * 
     * @param message
     *            The message to sign
     * @throws SecurityException
     *             Security exception
     */
    private void setupMessageSecurity(Message message) throws SecurityException {

        X509Certificate signingCertificate = (X509Certificate) message
                .get("dk.bankconnect.security.bankconnectcrypto.signing.certificate");
        if (signingCertificate != null) {
            try {
                this.signingCertificate = signingCertificate.getEncoded();
            } catch (CertificateEncodingException e) {
                SecurityException se = new SecurityException(e);
                se.setErrorcode(BankConnectConstants.INVALID_CERTIFICATE);
                throw se.getAsSoapFault();
            }
        }
        Key signingKey = (Key) message.get("dk.bankconnect.security.bankconnectcrypto.private.key");
        if (signingKey != null) {
            this.signingKey = signingKey.getEncoded();
        }
        X509Certificate encryptionCertificate = (X509Certificate) message
                .get("dk.bankconnect.security.bankconnectcrypto.encryption.certificate");
        if (encryptionCertificate == null) {
            encryptionCertificate = (X509Certificate) message.getExchange().get(
                    "dk.bankconnect.security.bankconnectcrypto.encryption.certificate");
        }
        if (encryptionCertificate != null) {
            try {
                this.encryptionCertificate = encryptionCertificate.getEncoded();
            } catch (CertificateEncodingException e) {
                SecurityException se = new SecurityException(e);
                se.setErrorcode(BankConnectConstants.INVALID_CERTIFICATE);
                throw se.getAsSoapFault();
            }
        }
    }

    public void handleFault(Message message) {
    }

    private class CachedStream extends CachedOutputStream {
        public CachedStream() {
            super(128L*1024L*1024L);
        }

        protected void doFlush() throws IOException {
            currentStream.flush();
        }

        protected void doClose() throws IOException {
        }

        protected void onWrite() throws IOException {
        }
    }

    public Set<QName> getUnderstoodHeaders() {
        return null;
    }
}

package dk.bankconnect.client;

import org.apache.log4j.Logger;
import org.w3c.dom.Document;

import dk.bankconnect.security.MessageChangeInterceptor;
import dk.bankconnect.security.SecurityException;
import dk.bankconnect.security.SecurityService;
import dk.bankconnect.security.SecurityServiceImpl;

/**
 * The ClientSecurityInterceptorOut class.
 * <p>
 * The ClientSecurityInterceptorOut class extends from the
 * MessageChangeInterceptor class.
 * 
 */
public class ClientSecurityInterceptorOut extends MessageChangeInterceptor {

    /*
     * Get logger object from this class.
     * 
     * @see dk.bankconnect.security.MessageChangeInterceptor#getLogger()
     */
    @Override
    protected Logger getLogger() {
        return Logger.getLogger(this.getClass());
    }

    /**
     * Returns the out bound message.
     * 
     * @param currentEnvelope
     * @param addSecurity
     *            not used
     * @throws SecurityException
     *             @see SecurityException
     * @return The out bound message
     */
    @Override
    protected Document changeOutboundMessage(Document currentEnvelope, Boolean addSecurity) throws SecurityException {

        SecurityService si = new SecurityServiceImpl();
        Document securedMessage = null;
        securedMessage = si.wrapSoapMessage(currentEnvelope, signingCertificate, signingKey, encryptionCertificate);
        return securedMessage;
    }

    @Override
    // TODO: SMO - Method inadequate, consider to fully implement method.
    protected String changeInboundMessage(String currentEnvelope) {
        return null;
    }

}

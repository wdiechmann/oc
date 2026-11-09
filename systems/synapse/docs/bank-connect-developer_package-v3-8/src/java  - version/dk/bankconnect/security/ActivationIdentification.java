package dk.bankconnect.security;

import org.apache.commons.lang.StringUtils;
import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.bouncycastle.asn1.ASN1ObjectIdentifier;
import org.bouncycastle.asn1.x500.RDN;
import org.bouncycastle.pkcs.PKCS10CertificationRequest;

import dk.bankconnect.BankConnectConstants;

/**
 * The ActivationIdentification class.
 * 
 */
public class ActivationIdentification {
    private Log logger = LogFactory.getFactory().getInstance(ActivationIdentification.class);

    private String activationCode;
    private String functionIdentification;

    /**
     * Constructor.
     * 
     * @param pkcs10CertificationRequest
     *            The pkcs10 formated certification request
     * @throws SecurityException
     *             Security exception
     */
    public ActivationIdentification(PKCS10CertificationRequest pkcs10CertificationRequest) throws SecurityException {

        RDN[] cnName = pkcs10CertificationRequest.getSubject().getRDNs(new ASN1ObjectIdentifier("2.5.4.3"));
        if ((cnName != null) && (cnName.length != 1)) {
            logger.error("No Common name (2.5.4.3)");
            SecurityException securityException = new SecurityException();
            securityException.setErrorcode(BankConnectConstants.VALIDATION_ERROR);
            throw securityException;
        } else {
            String commonName = cnName[0].getFirst().getValue().toString();
            if (commonName.contains("@")) {
                String[] split = commonName.split("@");
                if (split.length < 2) {
                    SecurityException securityException = new SecurityException(new Exception(
                            "Common name is invalid, functionid@activationcode pattern not found: " + commonName));
                    securityException.setErrorcode(BankConnectConstants.VALIDATION_ERROR);
                    throw securityException;
                }
                functionIdentification = split[0];
                activationCode = split[1];
            } else {
                functionIdentification = commonName;
            }
            logger.debug("Functionidentification from PKCS10 is: " + functionIdentification);
            logger.debug("ActivationCode from PKCS10 is: " + activationCode);
            if (StringUtils.isEmpty(functionIdentification)) {
                SecurityException securityException = new SecurityException(new Exception("Common name is invalid: "
                        + commonName));
                securityException.setErrorcode(BankConnectConstants.VALIDATION_ERROR);
                throw securityException;
            }
            if ((StringUtils.isNotEmpty(activationCode)) && (activationCode.length() != 16)) {
                SecurityException securityException = new SecurityException(new Exception("The length of the activationcode must be 16 characters"));
                securityException.setErrorcode(BankConnectConstants.VALIDATION_ERROR);
                throw securityException;
            }
        }
    }

    /**
     * Get the activation code.
     * 
     * @return The activation code
     */
    public String getActivationCode() {
        return activationCode;
    }

    /**
     * Get the function identification.
     * 
     * @return The function identification
     */
    public String getFunctionIdentification() {
        return functionIdentification;
    }

}

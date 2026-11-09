package dk.bankconnect.certificate;

import java.io.IOException;
import java.security.InvalidKeyException;
import java.security.NoSuchAlgorithmException;
import java.security.NoSuchProviderException;
import java.security.SignatureException;
import java.security.cert.CertPathValidatorException;
import java.security.cert.Certificate;
import java.security.cert.CertificateEncodingException;
import java.security.cert.CertificateException;
import java.security.cert.PKIXCertPathChecker;
import java.security.cert.X509Certificate;
import java.security.interfaces.RSAKey;
import java.util.Collection;
import java.util.Set;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.bouncycastle.asn1.x509.BasicConstraints;
import org.bouncycastle.asn1.x509.Extension;
import org.bouncycastle.asn1.x509.Extensions;
import org.bouncycastle.asn1.x509.KeyUsage;
import org.bouncycastle.cert.X509CertificateHolder;

/**
 * Implementing the rules in the Bank Connect certificate policy. The checker
 * validates </br>
 * <ul >
 * <li>Date</li>
 * <li>Version</li>
 * <li>Extensions</li>
 * <li>Keyusage</li>
 * <li>Public</li>
 * <li>Keysize</li>
 * <li>Algorithm</li>
 * </ul>
 * 
 * @author bdyaag
 */
public class BankConnectCertPathChecker extends PKIXCertPathChecker {

    /** The logger. */
    private Log logger = LogFactory.getFactory().getInstance(BankConnectCertPathChecker.class);
    /**
     * Not used.
     * 
     * @see java.security.cert.PKIXCertPathChecker#init(boolean)
     */
    @Override
    public void init(boolean forwardChecking) throws CertPathValidatorException {
    }

    /**
     * Not used.
     * 
     * @return - always false
     * 
     * @see java.security.cert.PKIXCertPathChecker#isForwardCheckingSupported()
     */
    @Override
    public boolean isForwardCheckingSupported() {
        return false;
    }

    /**
     * Not used.
     * 
     * @return always null
     * 
     * @see java.security.cert.PKIXCertPathChecker#getSupportedExtensions()
     */
    @Override
    public Set<String> getSupportedExtensions() {
        return null;
    }

    /**
     * Checks and validate CA, Intermidiate and entity certificates complies to
     * the Bank Connect policy.
     * 
     * @param certificate
     *            - the certificate to be checked
     * @param extensions
     *            - not used.
     * 
     * @see java.security.cert.PKIXCertPathChecker#check(java.security.cert.Certificate,
     *      java.util.Collection)
     * 
     * @throws CertPathValidatorException
     */
    @Override
    public void check(Certificate certificate, Collection<String> extensions) throws CertPathValidatorException {
        X509CertificateHolder certHolder = null;
        try {
            certHolder = new X509CertificateHolder(certificate.getEncoded());
            if(certHolder!=null) logger.debug("CertificateHolder found");
            try {
                validateGeneralRules((X509Certificate) certificate, certHolder);
            } catch (InvalidKeyException e) {
                throw new CertPathValidatorException("Invalid RSA key: " + e, e);
            } catch (CertificateException e) {
                throw new CertPathValidatorException("The certificate is not valid or cannot be verified: " + e, e);
            } catch (NoSuchAlgorithmException e) {
                throw new CertPathValidatorException("Wrong algorithme: " + e, e);
            } catch (NoSuchProviderException e) {
                throw new CertPathValidatorException("Provider unknown: " + e, e);
            } catch (SignatureException e) {
                throw new CertPathValidatorException("Signature is not valid" + e, e);
            }
            if (isCertificateEntity(certHolder.getExtensions())) {
                validateEntity((X509Certificate) certificate, certHolder);
            } else if ((certHolder.getExtension(Extension.subjectKeyIdentifier) != null)
                    && (certHolder.getExtension(Extension.authorityKeyIdentifier) != null)) {
                validateIntermidate((X509Certificate) certificate, certHolder);
            } else {
                validateCA((X509Certificate) certificate, certHolder);
            }
        } catch (CertificateEncodingException e) {
            throw new CertPathValidatorException("Not a valid BER/DER encoded X.509 certificate: " + e, e);
        } catch (IOException e) {
            throw new CertPathValidatorException("Encoded byte X.509 certificate is corrupted: " + e, e);
        } catch (CertPathValidatorException e) {
            throw new CertPathValidatorException(certHolder.getSubject() + " validation has failed: " + e, e);
        }
        logger.debug("Certificate check done");
    }

    /**
     * Determines if the certificate is an entity certificate base on the presence of basiccontraint extension and isCA is 
     * set to true.
     *
     * @param extensions certificate extensions
     * @return true if certificate do not contain a basicconstraint with true in isCA
     *         false if the certificate has true in isCA
     */
    private boolean isCertificateEntity(Extensions extensions) {
        boolean isEntity = true;
        Extension basicExtension = extensions.getExtension(Extension.basicConstraints);
        if (basicExtension != null) {
            BasicConstraints bc = BasicConstraints.fromExtensions(extensions);
            isEntity = !bc.isCA();
        }
        logger.debug("Is certificate an enitity certificate: "+(isEntity?"YES":"NO"));
        return isEntity;
    }

    /**
     * Validate entity certificate.
     * 
     * @param certificate
     *            the certificate
     * @param certHolder
     *            the certificate holder
     * @throws CertPathValidatorException
     */
    private void validateEntity(X509Certificate certificate, X509CertificateHolder certHolder)
            throws CertPathValidatorException {
        logger.debug("Validating enitity certificate rules");
        if(certificate==null) logger.debug("Certificate is NULL");
        if(certHolder==null) logger.debug("CertHolder is NULL");
        Extension authority = certHolder.getExtension(Extension.authorityKeyIdentifier);
        //TODO: Kontroller at feltet er markeret som non-critical.
        //TODO: Kontroller at KeyIdentifier ikke er tom
        if (authority == null) {
            logger.debug("Certificate validation failed. No 'Authority key identifier' extension available");
            throw new CertPathValidatorException(
                    "Certificate validation failed. No 'Authority key identifier' extension available");
        }
        if (certificate.getBasicConstraints() != -1) {
            logger.debug("Certificate must not contain basic constrains");
            throw new CertPathValidatorException("Certificate must not contain basic constrains");
        }
        KeyUsage keyUsage = KeyUsage.fromExtensions(certHolder.getExtensions());
        if (keyUsage != null) {
            logger.debug("Certificate keyusage not allowed. Refer to the correct keyusage in the policy document");
            throw new CertPathValidatorException(
                    "Certificate keyusage not allowed. Refer to the correct keyusage in the policy document");
        }
        
        //TODO: Kontrol af at levetid er 3 eller 5 år fra udstedelsesdato
        //TODO: Kontrol af at Subject findes
        //TODO: Kontroller at Subject Public Key info findes
        //TODO: Kontroller at Subject name findes
        //TODO: Kontroller at AlgorithmIdentifier er RSA 2048 bit
        //TODO: Kontroller at der findes en offentlig nøgle
        logger.debug("Validating enitity done");
    }

    /**
     * Validate CA certificate.
     * 
     * @param certificate
     *            the certificate
     * @param certHolder
     *            the certificate holder
     * @throws CertPathValidatorException
     */
    private void validateCA(X509Certificate certificate, X509CertificateHolder certHolder)
            throws CertPathValidatorException {
        logger.debug("Validating Root certificate rules");

        RSAKey rsaKey = (RSAKey) certificate.getPublicKey();
        if (rsaKey.getModulus().bitLength() != 4096) {
            throw new CertPathValidatorException("Publickey must be RSA and keysize 4096 bits");
        }
        if (certificate.getBasicConstraints() == -1) {
            throw new CertPathValidatorException("Certificate must contain basic constrains");
        }
        KeyUsage keyUsage = KeyUsage.fromExtensions(certHolder.getExtensions());
        if (!keyUsage.hasUsages(KeyUsage.keyCertSign)) {
            throw new CertPathValidatorException(
                    "Missing correct certificate keyusage. Refer to the correct keyusage in the policy document");
        }
        if (keyUsage.hasUsages(KeyUsage.dataEncipherment) || keyUsage.hasUsages(KeyUsage.decipherOnly)
                || keyUsage.hasUsages(KeyUsage.digitalSignature) || keyUsage.hasUsages(KeyUsage.encipherOnly)
                || keyUsage.hasUsages(KeyUsage.keyAgreement) || keyUsage.hasUsages(KeyUsage.keyEncipherment)
                || keyUsage.hasUsages(KeyUsage.nonRepudiation)) {
            throw new CertPathValidatorException(
                    "Missing correct certificate keyusage. Refer to the correct keyusage in the policy document");
        }
    }

    /**
     * Validate general certificate rules. Checks for
     * <ul>
     * <li>SHA256WITHRSA must be used</li>
     * <li>SubjecKeyIdentifier (2.5.29.14) is present</li>
     * <li>Version is 3</li>
     * </ul>
     * 
     * @param certificate
     *            the certificate
     * @param certHolder
     *            the certificate holder
     * @throws CertificateException
     *             the certificate exception
     * @throws InvalidKeyException
     *             the invalid key exception
     * @throws NoSuchAlgorithmException
     *             the no such algorithm exception
     * @throws NoSuchProviderException
     *             the no such provider exception
     * @throws SignatureException
     *             the signature exception
     * @throws CertPathValidatorException
     */
    private void validateGeneralRules(X509Certificate certificate, X509CertificateHolder certHolder)
            throws CertificateException, InvalidKeyException, NoSuchAlgorithmException, NoSuchProviderException,
            SignatureException, CertPathValidatorException {
        logger.debug("Validating general certificate rules");
        if(certificate==null) logger.debug("Certificate for validation is missing (null)");
        if(certHolder==null) logger.debug("CertHolder for validation is missing (null)");
        certificate.checkValidity();
        logger.debug("Validity of certificate has been verified");
        //TODO: Kontroller at der findes et serienummer på certifikatet
        //TODO: Kontrol af Issuer findes og at Issuer name indeholder valider værdier CN, O=(BEC,SDC el. BD), OU, C=DK 

        if (!"SHA256WITHRSA".equalsIgnoreCase(certificate.getSigAlgName().trim())) {
            logger.debug("SignatureAlgoritm wasn't SHA256WITHRSA");
            throw new NoSuchAlgorithmException("Invalid certificate signature algorithm. Must be SHA256WITHRSA is "
                    + certificate.getSigAlgName());
        }
        Extension subject = certHolder.getExtension(Extension.subjectKeyIdentifier);
        if (subject == null) {
            logger.debug("SubjectKeyIdentifier wasn't found");
            throw new CertPathValidatorException(
                    "Certificate validation failed. No 'Subject key identifier' extension available");
        }
        if (certHolder.getVersionNumber() != 3) {
            logger.debug("Certificate version number wasn't 3");
            throw new CertPathValidatorException("Certificate version failed. Must be version 3");
        }
        logger.debug("General rules validated");
    }

    /**
     * Validate intermidate certificate.
     * 
     * @param certificate
     *            the certificate
     * @param certHolder
     *            the certificate holder
     * @throws CertPathValidatorException
     */
    private void validateIntermidate(X509Certificate certificate, X509CertificateHolder certHolder)
            throws CertPathValidatorException {
        logger.debug("Validating intermediate certificate rules");
        RSAKey rsaKey = (RSAKey) certificate.getPublicKey();
        if (rsaKey.getModulus().bitLength() != 2048) {
            throw new CertPathValidatorException("Publickey must be RSA and keysize 2048 bits");
        }
        Extension authority = certHolder.getExtension(Extension.authorityKeyIdentifier);

        if (authority == null) {
            throw new CertPathValidatorException(
                    "Certificate validation failed. No 'Authority key identifier' extension available");
        }
        if (certificate.getBasicConstraints() == -1) {
            throw new CertPathValidatorException("Certificate must contain basic constrains");
        }
        KeyUsage keyUsage = KeyUsage.fromExtensions(certHolder.getExtensions());
        if (!keyUsage.hasUsages(KeyUsage.keyCertSign) || (!keyUsage.hasUsages(KeyUsage.digitalSignature))) {
            throw new CertPathValidatorException(
                    "Missing correct certificate keyusage. Refer to the correct keyusage in the policy document");
        }
        if (keyUsage.hasUsages(KeyUsage.dataEncipherment) || keyUsage.hasUsages(KeyUsage.decipherOnly)
                || keyUsage.hasUsages(KeyUsage.encipherOnly) || keyUsage.hasUsages(KeyUsage.keyAgreement)
                || keyUsage.hasUsages(KeyUsage.keyEncipherment) || keyUsage.hasUsages(KeyUsage.nonRepudiation)) {
            throw new CertPathValidatorException(
                    "Missing correct certificate keyusage. Refer to the correct keyusage in the policy document");
        }

    }

}

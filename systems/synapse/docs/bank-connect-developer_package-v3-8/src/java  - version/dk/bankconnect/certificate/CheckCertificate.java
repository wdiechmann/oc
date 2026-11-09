package dk.bankconnect.certificate;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.InputStream;
import java.security.InvalidAlgorithmParameterException;
import java.security.KeyStore;
import java.security.KeyStoreException;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.cert.CertPathValidatorException;
import java.security.cert.CertificateEncodingException;
import java.security.cert.CertificateException;
import java.security.cert.CertificateFactory;
import java.security.cert.PKIXParameters;
import java.security.cert.TrustAnchor;
import java.security.cert.X509Certificate;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;

import org.bouncycastle.util.encoders.Hex;

import dk.bankconnect.security.SecurityException;

/**
 * CheckCertificate verifies the Bank Connect certificate policy. See the
 * docs/Certificate-policy.pdf document.
 * 
 * Run the class as an application like:
 * 
 * java -cp bankconnect.jar;lib/* dk.bankconnect.certificate.CheckCertificate
 * c:/test.cert
 * 
 * @author bdyaag
 */
public class CheckCertificate {
    CertificateService certService;

    public CheckCertificate() {
        certService = new CertificateServiceImpl();
    }

    public static void main(String[] args) {
        CheckCertificate cc = new CheckCertificate();
        if (args.length < 4) {
            System.err
                    .println("Check and validate certificate. Keystore must contain trusted certificates (na defaults to bankconnect.jks) ");
            System.out.println("Parameters: ");
            System.out.println("1) policy|trust|all");
            System.out.println("2) entitycertificate filename");
            System.out.println("3) intermidiatecertificate filename");
            System.out.println("4) keystore (jks) filename - password must be bankconnect !");
            System.out.println();
            System.out
                    .println("exam: java -cp bankconnect.jar;lib/* dk.bankconnect.certificate.CheckCertificate policy c:/entity.cert c:/ia.cert c:/keystore.jks");
            System.out
                    .println("exam: java -cp bankconnect.jar;lib/* dk.bankconnect.certificate.CheckCertificate all c:/entity.cert na na");
            System.exit(1);
        }
        if (args[0].startsWith("policy")) {
            cc.validatePolicy(args[1]);
        }
        if (args[0].startsWith("trust")) {
            cc.validateTrust(args[1], args[2], args[3]);
        }
        if (args[0].startsWith("all")) {
            cc.validateAll(args[1], args[2], args[3]);
        }

    }

    private void validateAll(String entityFileName, String iaFileName, String keystoreFileName) {
        System.out.println("Entity certificate to be checked: " + entityFileName);
        System.out.println("IA certificate to be used for checked: " + iaFileName);
        try {
            List<X509Certificate> chainCertificates = new ArrayList<X509Certificate>();
            ArrayList<TrustAnchor> trustedCertificates = new ArrayList<TrustAnchor>();
            InputStream is = null;
            if (keystoreFileName.startsWith("na")) {
                is = this.getClass().getClassLoader().getResourceAsStream("bankconnect.jks");
            } else {
                is = new FileInputStream(keystoreFileName);
            }
            KeyStore keystore = KeyStore.getInstance(KeyStore.getDefaultType());
            String password = "bankconnect";
            keystore.load(is, password.toCharArray());
            // This class retrieves the most-trusted CAs from the keystore
            PKIXParameters params = new PKIXParameters(keystore);
            Iterator it = params.getTrustAnchors().iterator();
            while (it.hasNext()) {
                TrustAnchor ta = (TrustAnchor) it.next();
                trustedCertificates.add(ta);
            }
            File certFile = new File(entityFileName);
            X509Certificate cert = (X509Certificate) CertificateFactory.getInstance("X.509").generateCertificate(
                    new FileInputStream(certFile));
            chainCertificates.add(cert);
            File iaFile = new File(iaFileName);
            if (iaFile.exists()) {
                X509Certificate iaCert = (X509Certificate) CertificateFactory.getInstance("X.509").generateCertificate(
                        new FileInputStream(iaFile));
                chainCertificates.add(iaCert);
            }

            boolean validateEntityCertificate = certService.validateEntityCertificate(cert, chainCertificates,
                    trustedCertificates);
            System.out.println("Certificate is: " + validateEntityCertificate);
        } catch (CertificateException e) {
            System.err.println(e.getMessage());
        } catch (FileNotFoundException e) {
            System.err.println(e.getMessage());
        } catch (SecurityException e) {
            System.err.println(e);
        } catch (KeyStoreException e) {
            System.err.println(e.getMessage());
        } catch (NoSuchAlgorithmException e) {
            System.err.println(e.getMessage());
        } catch (IOException e) {
            System.err.println(e.getMessage());
        } catch (InvalidAlgorithmParameterException e) {
            System.err.println(e.getMessage());
        }
    }

    private void validateTrust(String entityFileName, String iaFileName, String keystoreFileName) {
        // TODO Auto-generated method stub

    }

    private void validatePolicy(String fileName) {
        InputStream fis;
        try {
            fis = new FileInputStream(new File(fileName));
            X509Certificate currentCertificate = (X509Certificate) CertificateFactory.getInstance("X.509")
                    .generateCertificate(fis);

            BankConnectCertPathChecker checker = new BankConnectCertPathChecker();
            try {
                checker.check(currentCertificate, null);
                System.out.println("Certificate is OK");
                System.out.println("Subject: " + currentCertificate.getSubjectDN());
                System.out.println("Fingerprint: " + getFingerprint(currentCertificate));
            } catch (CertPathValidatorException e) {
                System.err.println("Certificate is NOT ok");
                System.err.println(e.getMessage());
            }
        } catch (FileNotFoundException e) {
            System.err.println(e.getMessage());
        } catch (CertificateException e) {
            System.err.println(e.getMessage());
        }
    }

    private String getFingerprint(X509Certificate currentCertificate) {
        String fingerPrint = null;
        try {
            MessageDigest md = MessageDigest.getInstance("SHA1");
            byte[] encodedFingerprint = Hex.encode(md.digest(currentCertificate.getEncoded()));
            fingerPrint = new String(encodedFingerprint);
            fingerPrint = split(fingerPrint);
        } catch (CertificateEncodingException e) {
            System.err.println(e.getMessage());
        } catch (NoSuchAlgorithmException e) {
            System.err.println(e.getMessage());
        }
        return fingerPrint;
    }

    private String split(String fingerprint) {
        int no = 2;
        String newString = "";
        for (int i = 0; i < fingerprint.length() - 1; i = (i + no)) {
            newString += fingerprint.substring(i, i + no) + ":";
        }
        return newString.substring(0, newString.length() - 1);
    }
}

package dk.bankconnect.certificate;

import java.security.NoSuchAlgorithmException;

import javax.crypto.Cipher;

public class CheckJREForUnlimitedStrength {

    /*
     * @param args
     */
    public static void main(String[] args) {
        try {
            boolean isUnlimitedJCE = Cipher.getMaxAllowedKeyLength("AES") > 128;
            if (isUnlimitedJCE) {
                System.out.println("JCE Unlimited Strength Jurisdiction Policy is installed");
            } else {
                System.out.println("JCE Unlimited Strength Jurisdiction Policy is NOT installed");
            }
        } catch (NoSuchAlgorithmException e) {
            System.err.println("No AES algorithme is available");
        }
    }

}

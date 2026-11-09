package dk.bankconnect.security;

import java.io.IOException;
import java.util.HashMap;
import java.util.Map;

import javax.security.auth.callback.Callback;
import javax.security.auth.callback.CallbackHandler;
import javax.security.auth.callback.UnsupportedCallbackException;

import org.apache.ws.security.WSPasswordCallback;
/**
 * The UTPasswordCallback class.
 *
 */
public class UTPasswordCallback implements CallbackHandler {
    private static final String BANK_CERT = "erp-xyz";
    private static final String ERP_CERT = "bank connect-test";
    private String CERTIFICATE_PASSWORD="bankconnect";

    private Map<String, String> passwords = 
            new HashMap<String, String>();
        
        public UTPasswordCallback() {
            passwords.put(BANK_CERT, CERTIFICATE_PASSWORD);
            passwords.put(ERP_CERT, CERTIFICATE_PASSWORD);
        }

        /**
         * Here, we attempt to get the password from the private 
         * alias/passwords map.
         * 
         * @param callbacks
         *          The callbacks
         * 
         * @throws IOException
         *          I/O exception
         * @throws UnsupportedCallbackException
         *          Signals that a CallbackHandler does not recognize a particular Callback
         *          
         */
        public void handle(Callback[] callbacks) throws IOException, UnsupportedCallbackException {
            for (int i = 0; i < callbacks.length; i++) {
                WSPasswordCallback pc = (WSPasswordCallback)callbacks[i];

                String pass = passwords.get(pc.getIdentifier());
                if (pass != null) {
                    pc.setPassword(pass);
                    return;
                }
            }
        }

        /**
         * Add an alias/password pair to the callback mechanism.
         * 
         * @param alias
         *          The alias
         * @param password
         *          The password
         */
        public void setAliasPassword(String alias, String password) {
            passwords.put(alias, password);
        }

}

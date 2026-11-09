package dk.bankconnect.client;

import java.io.IOException;

import javax.security.auth.callback.Callback;
import javax.security.auth.callback.CallbackHandler;
import javax.security.auth.callback.UnsupportedCallbackException;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.apache.ws.security.WSPasswordCallback;


/**
 * 
 * Callback handler to returning password(s). Here a callback hander to the caller to resolve passwords during encryption 
 * and UsernameToken handling
 *
 */
public class PasswordCallback implements CallbackHandler {
    private Log logger = LogFactory.getFactory().getInstance(PasswordCallback.class);
    
    /*
     * "Returns" the password   
     * 
     * @return password set in array
     * 
     */
    @Override
    public void handle(Callback[] callbacks) throws IOException, UnsupportedCallbackException {
        WSPasswordCallback pc = (WSPasswordCallback) callbacks[0];
        pc.setPassword("bankconnect");
        logger.debug("WS password set!");
    }
}

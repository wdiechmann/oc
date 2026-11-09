package dk.bankconnect.server;

import javax.xml.ws.Endpoint;

import dk.bankconnect.certificate.CertificateServiceImpl;

/**
 * The CertificateServer class.
 */
public class CertificateServer {
    private Endpoint endpoint = null;

    /**
     * Stop the service.
     */
    public void stopCorporateService() {
        System.out.println("Stopping corporateservice");
        endpoint.stop();
    }

    /**
     * The main method.
     * 
     * @param args
     * @throws Exception @see Exception
     */
    public static void main(String args[]) throws Exception {
        if (args.length < 3) {
            System.out.println(CertificateServer.class.getName()
                    + " runs webservice for 30 minutes. 3 parameters - ip port context. Exam:");
            System.out.println("java -jar sh.jar ip 9000 bd");
            System.out.println("java -jar sh.jar ip 8000 bec");
            return;
        }

        CertificateServer server = new CertificateServer();
        System.out.println("Starting mockserver for 30 minutes and counting...");
        server.startCorporateService(args[0], args[1], args[2]);
        Thread.sleep(30 * 60 * 1000);
        System.out.println("Servicehandler exiting");
        server.stopCorporateService();
        System.exit(0);
    }   

    /**
     * Start the service.
     * <p>
     * http://"+ip+":"+port+"/"+context
     * 
     * @param ip for the service 
     * @param port the port for the service 
     * @param context the context for the service  
     */
    private void startCorporateService(String ip, String port, String context) {
        endpoint = Endpoint.publish("http://"+ip+":"+port+"/"+context, new CertificateServiceImpl());
        
    }
}
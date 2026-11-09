using System;

namespace SecuredClientTest
{
    public class RequestBuilder
    {
        public static ServiceHeader BuildServiceHeader()
        {
            var serviceHeader = new ServiceHeader
            {
                organisationIdentification = new organisationIdentification {isoCountryCode = "DK", mainRegistrationNumber = "3294"},
                functionIdentification = "12314123",
                erpInformation = new erpInformation {erpsystem = "asd", erpversion = "asd"},
                format = "xml",
                endToEndMessageId = Guid.NewGuid().ToString()
            };
            return serviceHeader;
        }

        public static ActivationHeader BuildActivationHeader()
        {
            var activationHeader = new ActivationHeader
            {
                organisationIdentification = new organisationIdentification {isoCountryCode = "DK", mainRegistrationNumber = "3294"},
                functionIdentification = "12314123",
                erpInformation = new erpInformation {erpsystem = "asd", erpversion = "asd"},
                endToEndMessageId = Guid.NewGuid().ToString()
            };
            return activationHeader;
        }
    }
}
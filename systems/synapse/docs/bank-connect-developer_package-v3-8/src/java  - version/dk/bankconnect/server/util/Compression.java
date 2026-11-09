package dk.bankconnect.server.util;

import java.io.IOException;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import com.google.common.io.ByteSource;

import dk.bankconnect.common.util.zip.GZIPCompressionUtility;

/**
 * Compression scheme applied to content data.
 * 
 * @author Morten Sabroe Mortensen/BDYMMN
 */
public enum Compression
{
    None(new String[]{"0","None"},null),
    GZIP(new String[]{"1","GZIP","gzip"},"application/gzip");
    
    Compression(String[] names,
                String mimeType)
    {
        this.names=Collections.unmodifiableList(Arrays.asList(names));
        this.mimeType=mimeType;
    }
    
    private List<String> names;
    private String mimeType;

    /**
     * 
     */
    public String getName()
    {
        return names.get(0);
    }

    /**
     * 
     */
    public String getMIMEType()
    {
        return mimeType;
    }
    
    /**
     * 
     */
    public ByteSource compress(ByteSource content) throws IOException
    {
        ByteSource res=null;
        
        {
            if (content!=null)
            {
                switch (this)
                {
                    case None:
                    {
                        res=content;
                        break;
                    }
                    
                    case GZIP:
                    {
                        res=GZIPCompressionUtility.compress(content);
                        break;
                    }
                    
                    default:
                    {
                        String message=
                            "Failure to compress content!";
                        throw new IllegalStateException(message);
                    }
                }
            }
        }
      
        return res;
    }

    /**
     * 
     */
    public ByteSource decompress(ByteSource content,
                                 Long limit) throws IOException
    {
        ByteSource res=null;
        
        {
            if (content!=null)
            {
                switch (this)
                {
                    case None:
                    {
                        res=content;
                        break;
                    }
                    
                    case GZIP:
                    {
                        res=GZIPCompressionUtility.decompress(content,limit);
                        break;
                    }
                    
                    default:
                    {
                        String message=
                            "Failure to decompress content!";
                        throw new IllegalStateException(message);
                    }
                }
            }
        }
      
        return res;
    }

    /**
     * 
     */
    public static Compression valueByName(String name)
    {
        Compression res=null;
        
        {
            if (name!=null)
            {
                Compression[] values=Compression.values();
                for (Compression value: values)
                {
                    if (value.names.contains(name))
                    {
                        res=value;
                        break;
                    }
                }
            }
        }
        
        return res;
    }
}

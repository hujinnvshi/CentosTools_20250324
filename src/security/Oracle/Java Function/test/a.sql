create or replace and compile java source named mac32tomac64 as
public class Mac32ToMac64 {
    public static byte[] hex2byte(java.lang.String hex)
            throws Exception {
        if (hex.length() % 2 != 0) {
            throw new Exception();
        }
        char[] arr = hex.toCharArray();
        byte[] b = new byte[hex.length() / 2];

        for (int i = 0, j = 0, l = hex.length(); i < l; i++, j++) {

            java.lang.String swap = "" + arr[i++] + arr[i];

            int byteint = java.lang.Integer.parseInt(swap, 16) & 0xFF;

            b[j] = new java.lang.Integer(byteint).byteValue();

        }

        return b;

    }

    public static java.lang.String byte2hex(byte[] b) {

        java.lang.StringBuffer hs = new java.lang.StringBuffer();

        java.lang.String stmp;

        for (int i = 0; i < b.length; i++) {

            stmp = java.lang.Integer.toHexString(b[i] & 0xFF).toUpperCase();

            if (stmp.length() == 1) {

                hs.append("0").append(stmp);

            } else {

                hs.append(stmp);

            }

        }

        return hs.toString();

    }

    public static byte[] lengthen(byte[] byteArray) {

        byte[] result = new byte[byteArray.length * 2];

        for (int i = 0; i < byteArray.length; i++) {

            result[2 * i] = byteArray[i];

            int value = (byteArray[i] + byteArray[i == byteArray.length - 1 ? 0 : i + 1]) & 0xFF;

            result[2 * i + 1] = new java.lang.Integer(value).byteValue();

        }

        return result;

    }

    public static java.lang.String to64Mac(java.lang.String req32Mac)

            throws Exception {

        byte[] bytes = hex2byte(req32Mac);

        if (bytes.length == 16) {

            return byte2hex(lengthen(bytes));

        } else {

            throw new Exception("");

        }

    }

}


CREATE OR REPLACE FUNCTION to64mac(r IN VARCHAR2) RETURN VARCHAR2 AS
LANGUAGE JAVA NAME 'Mac32ToMac64.to64Mac(java.lang.String) return String';

SELECT * FROM all_errors 
WHERE owner = 'SYS' 
AND name = 'TO64MAC' 
AND type = 'FUNCTION' 
ORDER BY sequence;


-- 测试用例1：标准32位MAC地址转64位
SELECT to64mac('1234567890ABCDEF1234567890ABCDEF') AS result_1 FROM dual;

-- 测试用例2：全数字MAC地址
SELECT to64mac('12345678901234567890123456789012') AS result_2 FROM dual;

-- 测试用例3：全字母MAC地址
SELECT to64mac('AABBCCDDEEFFAABBCCDDEEFFAABBCCDD') AS result_3 FROM dual;
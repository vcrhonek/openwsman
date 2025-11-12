#!/bin/sh -e

CERTFILE=@WSMANCONF_DIR@/servercert.pem
KEYFILE=@WSMANCONF_DIR@/serverkey.pem
CNFFILE=@WSMANCONF_DIR@/ssleay.cnf
CAFILE=@WSMANCONF_DIR@/ca.crt
DAYS=365

function show_usage() {
    echo "Usage: $0 [--force|--backup]"
    echo "  --force   : Overwrite existing certificates"
    echo "  --backup  : Backup existing certificates before creating new ones"
    exit 1
}

function create_ssl_cnf
{
    # Get minimum RSA key length at current security level
    # This workarounds openssl not enforcing min. key length enforced by current security level
    KEYSIZE=`grep min_rsa_size /etc/crypto-policies/state/CURRENT.pol | cut -d ' ' -f 3`
    # Validate KEYSIZE is actually a number
    if ! echo "$KEYSIZE" | grep -q '^[0-9]\+$'; then
        echo "Warning: Invalid key size '$KEYSIZE', using 2048"
        KEYSIZE=2048
    fi

    # Create OpenSSL configuration files for generating certificates
    echo "[ req ]" > $CNFFILE
    echo "default_bits            = $KEYSIZE" >> $CNFFILE
    echo "default_keyfile         = privkey.pem" >> $CNFFILE
    echo "distinguished_name      = req_distinguished_name" >> $CNFFILE

    echo "[ req_distinguished_name ]" >> $CNFFILE
    echo "countryName                     = Country Name (2 letter code)" >> $CNFFILE
    echo "countryName_default             = GB" >> $CNFFILE
    echo "countryName_min                 = 2" >> $CNFFILE
    echo "countryName_max                 = 2" >> $CNFFILE

    echo "stateOrProvinceName             = State or Province Name (full name)" >> $CNFFILE
    echo "stateOrProvinceName_default     = Some-State" >> $CNFFILE

    echo "localityName                    = Locality Name (eg, city)" >> $CNFFILE

    echo "organizationName                = Organization Name (eg, company; recommended)" >> $CNFFILE
    echo "organizationName_max            = 64" >> $CNFFILE

    echo "organizationalUnitName          = Organizational Unit Name (eg, section)" >> $CNFFILE
    echo "organizationalUnitName_max      = 64" >> $CNFFILE

    echo "commonName                      = server name (eg. ssl.domain.tld; required!!!)" >> $CNFFILE
    echo "commonName_max                  = 80" >> $CNFFILE

    echo "emailAddress                    = Email Address" >> $CNFFILE
    echo "emailAddress_max                = 85" >> $CNFFILE
}

function selfsign_sscg()
{
    sscg --quiet \
         --lifetime "$DAYS" \
         --cert-key-file "$KEYFILE" \
         --cert-file "$CERTFILE" \
         --ca-file "$CAFILE"
}

function selfsign_openssl()
{
    echo
    echo creating selfsigned certificate
    echo "replace it with one signed by a certification authority (CA)"
    echo
    echo enter your ServerName at the Common Name prompt
    echo

    # use special .cnf, because with normal one no valid selfsigned
    # certificate is created

    openssl req -days $DAYS $@ -config $CNFFILE \
        -newkey rsa:$KEYSIZE -x509 -nodes -out $CERTFILE \
        -keyout $KEYFILE
    chmod 600 $KEYFILE
}

if [ "$1" = "--help" -o "$1" = "-h" ]; then
    show_usage
fi

if [ "$1" != "--force" -a "$1" != "--backup" -a -f "$KEYFILE" ]; then
    echo "$KEYFILE exists!"
    echo "Use '$0 --force' to overwrite, or '$0 --backup' to backup first"
    exit 0
fi

if [ "$1" = "--backup" ]; then
    if [ -f "$KEYFILE" ]; then
        cp "$KEYFILE" "$KEYFILE.bak.$(date +%Y%m%d-%H%M%S)"
        cp "$CERTFILE" "$CERTFILE.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
        echo "Backed up existing certificates"
    fi
    force_mode="true"
    shift
fi

if [ "$1" = "--force" ]; then
    force_mode="true"
    shift
fi

# Remove existing files when using --force or --backup
if [ "$force_mode" = "true" ]; then
    rm -f "$KEYFILE" "$CERTFILE" "$CAFILE" 2>/dev/null
fi

create_ssl_cnf

# Try sscg first (modern tool), fallback to openssl if not available
if command -v sscg >/dev/null 2>&1; then
    selfsign_sscg || selfsign_openssl
else
    selfsign_openssl
fi

# Certificate validation
if [ -f "$CERTFILE" ] && [ -f "$KEYFILE" ]; then
    echo "Certificate generated successfully:"
    echo "  Certificate: $CERTFILE"
    echo "  Private key: $KEYFILE ($(stat -c%a "$KEYFILE") permissions)"
    echo "  Key size: $(openssl rsa -in "$KEYFILE" -text -noout 2>/dev/null | grep "Private-Key:" | grep -o '[0-9]\+ bit' || echo "unknown bits")"
else
    echo "Error: Certificate generation failed"
    exit 1
fi

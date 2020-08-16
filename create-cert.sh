#!/bin/sh
#Use openssl to create an x509 self-signed certificate authority (CA)
#certificate signing request (CSR), and resulting private key with IP SAN and DNS SAN

SERV=minio

COUNTRY=IN
STATE=WestBengal
LOCALITY=Kolkata
ORG="Cloud Cafe"

HOST_IP=`ip -o -4 addr list eth0 | awk '{print $4}' | cut -d/ -f1`

# Define where to store the generated certs and metadata.
DIR="$(pwd)/tls"

# Optional: Ensure the target directory exists and is empty.
rm -rf "${DIR}"
mkdir -p "${DIR}"

# Generate private key for CA cert
openssl genrsa -out "${DIR}/rootCA.key" 4096

# Generate public key (certificate) for the CA
openssl req \
  -x509 \
  -new \
  -sha256 \
  -days 1825 \
  -nodes \
  -subj "/C=$COUNTRY/ST=$STATE/L=$LOCALITY/O=$ORG" \
  -keyout "${DIR}/rootCA.key" \
  -out "${DIR}/rootCA.pem"

# Generate private key for MINIO
openssl genrsa -out "${DIR}/private.key" 2048

# Generate public key (certificate) for MinIO
openssl req -subj "/CN=$HOST_IP" -sha256 -new -key "${DIR}/private.key" -out "${DIR}/cert.csr"

# Using the CA private key sign the above created CSR to issue the cert

cat > "${DIR}/extfile.conf" << EOF
subjectAltName = IP:IIIIIIIIII
EOF

sed -i "s/IIIIIIIIII/$HOST_IP/" ${DIR}/extfile.conf

openssl x509 \
  -req \
  -days 365 \
  -sha256 \
  -in "${DIR}/cert.csr" \
  -CA "${DIR}/rootCA.pem" \
  -CAkey "${DIR}/rootCA.key" \
  -CAcreateserial \
  -out "${DIR}/public.crt" \
  -extfile ${DIR}/extfile.conf

# (Optional) Verify the certificate.
openssl x509 -in "${DIR}/public.crt" -noout -text

#

provider "aws" {
  region = "eu-central-1"
}

variable "vpn_psk_1" {}
variable "vpn_psk_2" {}

#######################################################################################################################
# Define VPC and Subnets
#######################################################################################################################

resource "aws_vpc" "0" {
  cidr_block = "172.20.0.0/16"
  tags {
    Name = "TEST for VPN debugging"
  }
}

resource "aws_subnet" "pub" {
  vpc_id     = "${aws_vpc.0.id}"
  availability_zone = "eu-central-1a"
  cidr_block = "172.20.1.0/24"
  tags {
    Name = "vpndebug-Public"
  }
}

resource "aws_subnet" "priv" {
  vpc_id     = "${aws_vpc.0.id}"
  availability_zone = "eu-central-1b"
  cidr_block = "172.20.2.0/24"
  tags {
    Name = "vpndebug-Private"
  }
}

#######################################################################################################################
# Define Gateways: NAT / Internet
#######################################################################################################################

# a NAT gateway needs an elastic IP

resource "aws_eip" "nat" {
  vpc = true
  tags {
    Name = "vpndebug"
  }
}

# a NAT gateway must be placed into a public subnet

resource "aws_nat_gateway" "0" {
  subnet_id     = "${aws_subnet.pub.id}"
  allocation_id = "${aws_eip.nat.id}"
  tags {
    Name = "vpndebug"
  }
}

# internet gateway for public access

resource "aws_internet_gateway" "0" {
  vpc_id = "${aws_vpc.0.id}"
  tags {
    Name = "vpndebug"
  }
}


#######################################################################################################################
# Routing tables
#######################################################################################################################

# define two route tables, private and public

resource "aws_route_table" "priv" {
  vpc_id = "${aws_vpc.0.id}"
  tags {
    Name = "vpndebug-priv"
  }
}

resource "aws_route_table" "pub" {
  vpc_id = "${aws_vpc.0.id}"
  tags {
    Name = "vpndebug-pub"
  }
}

# the private table gets the NAT gateway as defaultroute

#resource "aws_route" "priv" {
#  route_table_id         = "${aws_route_table.priv.id}"
#  destination_cidr_block = "0.0.0.0/0"
#  nat_gateway_id         = "${aws_nat_gateway.0.id}"
#}

resource "aws_route" "priv-vpn" {
  route_table_id         = "${aws_route_table.priv.id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_vpn_gateway.this.id}"
}

# the public table gets the Internet gateway as defaultroute

resource "aws_route" "pub01" {
  route_table_id         = "${aws_route_table.pub.id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id         = "${aws_internet_gateway.0.id}"
}

resource "aws_route" "pub02" {
  route_table_id         = "${aws_route_table.pub.id}"
  destination_cidr_block = "169.254.11.2/32"
  gateway_id         = "${aws_vpn_gateway.this.id}"
}

# associate the route tables to the respective subnets
# private

resource "aws_route_table_association" "priv" {
  subnet_id      = "${aws_subnet.priv.id}"
  route_table_id = "${aws_route_table.priv.id}"
}

# and public

resource "aws_route_table_association" "pub" {
  subnet_id      = "${aws_subnet.pub.id}"
  route_table_id = "${aws_route_table.pub.id}"
}


#######################################################################################################################
# VPN
#######################################################################################################################

resource "aws_vpn_gateway" "this" {
  vpc_id = "${aws_vpc.0.id}"
  tags {
    Name = "TEST"
  }
}

resource "aws_customer_gateway" "this" {
  bgp_asn    = 65000
  ip_address = "37.221.194.129"
  type       = "ipsec.1"
  tags {
    Name = "TEST"
  }
}

resource "aws_vpn_connection" "this" {
  vpn_gateway_id      = "${aws_vpn_gateway.this.id}"
  customer_gateway_id = "${aws_customer_gateway.this.id}"
  type                = "ipsec.1"
  static_routes_only  = true
  tunnel1_preshared_key = "${var.vpn_psk_1}"
  tunnel2_preshared_key = "${var.vpn_psk_2}"
  tunnel1_inside_cidr = "169.254.10.0/30"
  tunnel2_inside_cidr = "169.254.11.0/30"
  tags {
    Name = "TEST"
  }
}

resource "aws_vpn_connection_route" "this" {
  destination_cidr_block = "169.254.11.2/32"
  vpn_connection_id      = "${aws_vpn_connection.this.id}"
}

#######################################################################################################################
# EC2 helper resources
#######################################################################################################################

resource "aws_security_group" "ssh" {
  name        = "ssh"
  vpc_id      = "${aws_vpc.0.id}"
  description = "Allow ssh from everywhere"
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "6"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}

resource "aws_key_pair" "tg" {
  key_name   = "Tobias Galitzien"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDPiRwfuCc98FbFXhadNJwAav81EVdgp8KEH88X5GLhYZdKqf0AFtaRoEod5qIilSrbol+w2tC/CtX0bSmN+dMyDx7ELZoKWe2BEyrkJc1w4fUunaabB0NBWIzoZLZCLchQ18gTRX8IDb0Uj2HhFp2DCAr6sFUVBERAKjbCOZTaUqlICmwFFJwwa8FFzoEbr0FbHgeFUqSA+WaK6ZNBCFZp9SJLkP/dXjJ7Yq3ToZD1FiHgbDCZ6lbc04Ztqo8h0Meizmbmv8ZMs3J1t1zdTFJa5qqS7oxO+GvL0Bpf4q26eZrsecEfz2Uf5E+Tx9TQwi5UBYQGLIrkTfSAHCGqxahZ Tobias Galitzien"
}

resource "aws_route53_record" "pub" {
    name = "vpntest"
    type = "A"
    zone_id = "ZLSY18MTN4TU8"
    ttl = "1"
    records = ["${aws_instance.pub.public_ip}"]
}

resource "aws_route53_record" "priv" {
    name = "vpntest-priv"
    type = "A"
    zone_id = "ZLSY18MTN4TU8"
    ttl = "1"
    records = ["${aws_instance.priv.private_ip}"]
}


#######################################################################################################################
# EC2 Instances
#######################################################################################################################

resource "aws_instance" "pub" {
    ami = "ami-89163e62" # bionic
    instance_type = "t2.micro"
    key_name = "${aws_key_pair.tg.key_name}"
    user_data = <<-AMEN
        #!/bin/bash
        #apt-get -y update
        #apt-get -y -q install python
        AMEN
    tags {
        Name = "vpn-debugging-pub"
    }
    vpc_security_group_ids = ["${aws_security_group.ssh.id}"]
    subnet_id = "${aws_subnet.pub.id}"
    associate_public_ip_address = true
}

resource "aws_instance" "priv" {
    ami = "ami-89163e62" # bionic
    instance_type = "t2.micro"
    key_name = "${aws_key_pair.tg.key_name}"
    user_data = <<-AMEN
        #!/bin/bash
        #apt-get -y update
        #apt-get -y -q install python
        AMEN
    tags {
        Name = "vpn-debugging-priv"
    }
    vpc_security_group_ids = ["${aws_security_group.ssh.id}"]
    subnet_id = "${aws_subnet.priv.id}"
}

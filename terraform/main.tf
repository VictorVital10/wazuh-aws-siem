# EC2 INSTANCE FOR LINUX WAZUH AGENT
resource "aws_instance" "linux_agent" {
  ami                    = var.instance_ami
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.agents_sg.id]     #Attaches the SG controlling inbound/outbound traffic.
  key_name               = aws_key_pair.wazuh_agent_key.key_name #Attaches the SSH key to the instance.

  tags = {
    Name = "Linux Agent"
  }
}

# SECURITY GROUP FOR LINUX WAZUH AGENT
resource "aws_security_group" "agents_sg" {
  name        = "agents_sg"
  description = "SG for Wazuh Agents"
  vpc_id      = var.vpc_id
}

# INGRESS RULES FOR SG
#resource "aws_vpc_security_group_ingress_rule" "ssh_personal" {
# description       = "Allow SSH from personal IP"
#security_group_id = aws_security_group.agents_sg.id
#from_port         = 22
#to_port           = 22
#ip_protocol       = "tcp"
#cidr_ipv4         = var.personal_ip
#}

 resource "aws_vpc_security_group_ingress_rule" "ssh_professional" {
 description       = "Allow SSH from professional IP"
security_group_id = aws_security_group.agents_sg.id
from_port         = 22
to_port           = 22
ip_protocol       = "tcp"
cidr_ipv4         = var.professional_ip
}

# EGRESS RULES FOR SG
resource "aws_vpc_security_group_egress_rule" "allow_all_outbound" {
  security_group_id = aws_security_group.agents_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # All protocols
  description       = "Allow all outbound traffic"
}

resource "aws_key_pair" "wazuh_agent_key" {
  key_name   = "wazuh_agent_key"
  public_key = file(var.public_key_path)
}

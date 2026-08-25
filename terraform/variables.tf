variable "aws_region" {
  type    = string
  default = "us-east-2"
}

variable "aws_profile" {
  type    = string
  default = "Terraform"
}

variable "instance_ami" {
  type    = string
  default = "ami-0e5497a77ef21b5ac"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "vpc_id" {
  type    = string
  default = "vpc-06ff848d9b6540e15"
}

variable "professional_ip" {
  description = "My professional PC's public IP"
  type        = string
}

variable "public_key_path" {
  description = "Path tp the SSH public key"
  type        = string
}
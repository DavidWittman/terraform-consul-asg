variable "vpc_id" {}

variable "subnet_ids" {
  type = "list"
}

variable "key_name" {}

variable "cluster_name" {
  default     = "consul-asg"
  description = "Identifier for the ASG. This value is used to discover the other Consul servers via tags"
}

variable "instance_type" {
  default = "t2.medium"
}

variable "min_size" {
  default = 3
}

variable "max_size" {
  default = 3
}

variable "desired_capacity" {
  default     = 3
  description = "Set the desired capacity of the auto-scaling group. This value is also used as the -bootstrap-expect option when starting the consul server."
}

data "template_file" "install" {
  template = "${file("${path.module}/scripts/install.sh")}"

  vars {
    CLUSTER_NAME     = "${var.cluster_name}"
    DATACENTER       = "${var.region}"
    BOOTSTRAP_EXPECT = "${var.desired_capacity}"
  }
}

data "aws_ami" "centos" {
  most_recent = true

  filter {
    name   = "name"
    values = ["CentOS Linux 7 x86_64 HVM EBS*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["410186602215"] # CentOS
}

resource "aws_iam_policy" "consul" {
  name        = "consul-ec2-describe"
  description = "Allow Consul Servers to describe EC2 instances"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Action": "ec2:DescribeInstances",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role" "consul" {
  name        = "consul-server"
  description = "Assumed by Consul servers to discover via EC2 tags"
  path        = "/"

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {
               "Service": "ec2.amazonaws.com"
            },
            "Effect": "Allow",
            "Sid": ""
        }
    ]
}
EOF
}

resource "aws_iam_policy_attachment" "consul" {
  name       = "consul-attachment"
  roles      = ["${aws_iam_role.consul.name}"]
  policy_arn = "${aws_iam_policy.consul.arn}"
}

resource "aws_iam_instance_profile" "consul" {
  name = "consul-server"
  role = "${aws_iam_role.consul.name}"
}

resource "aws_security_group" "consul" {
  name        = "consul-internal"
  description = "Allow Serf and Consul traffic between servers in the cluster"
  vpc_id      = "${var.vpc_id}"

  ingress {
    from_port = 8300
    to_port   = 8302
    protocol  = "tcp"
    self      = true
  }

  # TODO: Remove
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_launch_configuration" "consul" {
  name_prefix   = "consul-lc-"
  image_id      = "${data.aws_ami.centos.id}"
  instance_type = "${var.instance_type}"
  key_name      = "${var.key_name}"

  iam_instance_profile = "${aws_iam_instance_profile.consul.arn}"
  associate_public_ip_address = true
  security_groups      = ["${aws_security_group.consul.id}"]
  user_data            = "${data.template_file.install.rendered}"

  root_block_device {
    volume_type = "gp2"
    volume_size = 40
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "consul" {
  name                 = "${var.cluster_name} - ${aws_launch_configuration.consul.name}"
  launch_configuration = "${aws_launch_configuration.consul.name}"
  vpc_zone_identifier  = "${var.subnet_ids}"

  min_size         = "${var.min_size}"
  max_size         = "${var.max_size}"
  desired_capacity = "${var.desired_capacity}"

  health_check_type = "EC2"

  tag {
    key                 = "Name"
    value               = "${var.cluster_name}-server"
    propagate_at_launch = true
  }

  tag {
    key                 = "ConsulCluster"
    value               = "${var.cluster_name}"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

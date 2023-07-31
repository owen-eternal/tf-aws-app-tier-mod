#################################################
################ Modules ########################
#################################################

module "tf-aws-network" {
  source          = "git@github.com:owen-eternal/tf-aws-network-mod.git"
  vpc_cdir        = var.vpc_cdir
  project_name    = var.project_name
  environment     = terraform.workspace
  web_server_port = var.web_server_port
  database        = var.database
  db_server_port  = var.db_server_port
  subnet_cdir     = var.subnet_cdir
  ipaddr          = var.ipaddr
}

#################################################
################ local #########################
#################################################

locals {
  http_port = module.tf-aws-network.application_port
}

################################################
############### Resources ######################
################################################

resource "aws_launch_template" "launch-blueprint" {
  image_id               = var.app_ami
  instance_type          = var.app_instance_type
  key_name               = var.ssh_key_pair
  name_prefix            = "${module.tf-aws-network.tag_name}-asg"
  user_data              = filebase64(var.user_data)
  vpc_security_group_ids = [module.tf-aws-network.web_security_group_id]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "web-asg" {
  min_size            = 2
  max_size            = 4
  desired_capacity    = 2
  vpc_zone_identifier = module.tf-aws-network.web_subnet_ids

  launch_template {
    id      = aws_launch_template.launch-blueprint.id
    version = "$Default"
  }

  lifecycle {
    ignore_changes = [max_size, target_group_arns]
  }
}

resource "aws_lb" "web-lb" {
  name               = "${module.tf-aws-network.tag_name}-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [module.tf-aws-network.lb_security_group_id]
  subnets            = module.tf-aws-network.web_subnet_ids
}

resource "aws_lb_listener" "http-listener" {
  load_balancer_arn = aws_lb.web-lb.arn
  port              = local.http_port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web-tg.arn
  }
}

resource "aws_lb_target_group" "web-tg" {
  name     = "${module.tf-aws-network.tag_name}-tg"
  port     = local.http_port
  protocol = "HTTP"
  vpc_id   = module.tf-aws-network.vpc_id
}

resource "aws_autoscaling_attachment" "app-atg-tg-att" {
  autoscaling_group_name = aws_autoscaling_group.web-asg.id
  lb_target_group_arn    = aws_lb_target_group.web-tg.arn
}
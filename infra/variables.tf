variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-northeast-2"   # 서울 리전
}

variable "key_pair_name" {
  description = "EC2 Key Pair 이름"           
  type        = string
}

variable "instance_type" {
  description = "EC2 인스턴스 타입"
  type        = string
  default     = "t2.micro"
}

variable "db_username" {
  description = "RDS DB 사용자 이름(자유)"   
  type        = string
  default     = "admin"
}

variable "db_password" {
  description = "RDS DB 비밀번호"
  type        = string
  sensitive   = true
}


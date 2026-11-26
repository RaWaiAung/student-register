import { IsNotEmpty, IsString, MaxLength, MinLength } from 'class-validator';

export class CreateStudentDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(100)
  name: string;

  @IsString()
  @MinLength(6)
  @MaxLength(100)
  password: string;
}

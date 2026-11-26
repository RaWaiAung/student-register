import { ConflictException, Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import * as bcrypt from 'bcryptjs';
import { PrismaService } from '../prisma.service';
import { CreateStudentDto } from './create-student.dto';

// Never send the password hash back to the client
const publicFields = { id: true, name: true, createdAt: true } as const;

@Injectable()
export class StudentsService {
  constructor(private readonly prisma: PrismaService) {}

  findAll() {
    return this.prisma.student.findMany({
      select: publicFields,
      orderBy: { id: 'desc' },
    });
  }

  async create(dto: CreateStudentDto) {
    const password = await bcrypt.hash(dto.password, 10);
    try {
      return await this.prisma.student.create({
        data: { name: dto.name.trim(), password },
        select: publicFields,
      });
    } catch (e) {
      if (
        e instanceof Prisma.PrismaClientKnownRequestError &&
        e.code === 'P2002'
      ) {
        throw new ConflictException('This name is already registered');
      }
      throw e;
    }
  }
}

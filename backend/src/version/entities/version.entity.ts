import {
  Entity,
  Column,
  PrimaryGeneratedColumn,
  CreateDateColumn,
} from 'typeorm';

@Entity()
export class Version {
  @PrimaryGeneratedColumn()
  id: number;

  @Column()
  version: string;

  @Column()
  timestamp: Date;

  @Column({ default: true })
  isActive: boolean;

  @Column({ default: false })
  forceUpdate: boolean;

  @CreateDateColumn()
  createdAt: Date;
}

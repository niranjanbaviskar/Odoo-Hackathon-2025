export interface Skill {
  name: string;
  description: string;
  importance: string;
}

export interface Resource {
  name: string;
  type: string;
  url?: string;
  description: string;
  format: "Text" | "Video" | "Interactive";
  difficulty: "Beginner" | "Intermediate" | "Advanced";
  estimated_time: string;
  prerequisites: string[];
  cost: "Free" | "Paid" | "Subscription";
}

export interface Project {
  name: string;
  description: string;
  learning_objectives: string[];
  features: string[];
  skills_practiced: string[];
  difficulty: "Beginner" | "Intermediate" | "Advanced";
  estimated_time: string;
  resources: string[];
  next_steps: string[];
}

export interface BestPractice {
  title: string;
  description: string;
  examples: string[];
}

export interface Pitfall {
  issue: string;
  solution: string;
}

export interface Tool {
  name: string;
  category: string;
  description: string;
  url: string;
  setup_guide: string;
  alternatives: string[];
  pros: string[];
  cons: string[];
}

export interface Certification {
  name: string;
  provider: string;
  level: "Beginner" | "Intermediate" | "Advanced";
  description: string;
  url: string;
  cost: string;
  validity: string;
  preparation_resources: string[];
}

export interface CareerPath {
  roles: string[];
  skills_required: string[];
  progression: string[];
  salary_range: string;
}

export interface RoadmapStage {
  level: "Beginner" | "Intermediate" | "Advanced";
  title: string;
  description: string;
  skills: Skill[];
  resources: Resource[];
  timeframe: string;
  projects: Project[];
  best_practices: BestPractice[];
  common_pitfalls: Pitfall[];
}

export interface Roadmap {
  id?: string;
  title: string;
  description: string;
  stages: RoadmapStage[];
  tools: Tool[];
  certifications: Certification[];
  career_path: CareerPath;
  user_id?: string;
  created_at?: string;
  updated_at?: string;
}

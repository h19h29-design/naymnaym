import { useState, type ReactNode } from "react";
import {
  Apple,
  Bell,
  CalendarCheck,
  CalendarDays,
  Check,
  ChevronDown,
  Database,
  Download,
  HeartHandshake,
  LockKeyhole,
  Mail,
  Menu,
  Search,
  ShieldCheck,
  Sparkles,
  Star,
  Utensils,
  X,
} from "lucide-react";

type IconType = typeof CalendarCheck;

type NavItem = {
  id: string;
  label: string;
};

type Feature = {
  title: string;
  description: string;
  icon: IconType;
};

type Preview = {
  title: string;
  heading: string;
  rows: string[];
  action?: string;
  accent?: string;
};

type Level = {
  level: string;
  name: string;
  detail: string;
};

const navItems: NavItem[] = [
  { id: "intro", label: "앱 소개" },
  { id: "features", label: "주요 기능" },
  { id: "preview", label: "화면 미리보기" },
  { id: "levelup", label: "레벨업" },
  { id: "data", label: "활용 데이터" },
  { id: "privacy", label: "개인정보 보호" },
  { id: "launch", label: "출시 안내" },
];

const trustCards = [
  "회원가입 없음",
  "기기 내부 저장",
  "무료 사용",
  "광고 없음",
];

const features: Feature[] = [
  {
    title: "오늘 급식 확인",
    description: "학교별 오늘 식단과 월간 급식을 한눈에 확인합니다.",
    icon: CalendarCheck,
  },
  {
    title: "월간 급식 캘린더",
    description: "다가오는 메뉴를 미리 보고 한 달 식습관을 준비합니다.",
    icon: CalendarDays,
  },
  {
    title: "칼로리와 영양정보",
    description: "칼로리, 탄수화물, 단백질, 지방 등 핵심 정보를 쉽게 봅니다.",
    icon: ShieldCheck,
  },
  {
    title: "안 먹는 반찬 클릭",
    description: "먹기 어려운 반찬을 누르면 놓칠 수 있는 영양소를 알려줍니다.",
    icon: Utensils,
  },
  {
    title: "한 입 도전과 레벨업",
    description: "작은 도전을 기록하고 경험치와 뱃지로 성장을 확인합니다.",
    icon: Star,
  },
  {
    title: "보호자 주간 요약",
    description: "편식 경향과 도전 기록을 보호자가 이해하기 쉽게 정리합니다.",
    icon: HeartHandshake,
  },
];

const previews: Preview[] = [
  {
    title: "학교 검색",
    heading: "학교 검색",
    rows: ["명랑초등학교", "냠냠중학교", "튼튼고등학교"],
    action: "학교 선택",
    accent: "green",
  },
  {
    title: "오늘 급식",
    heading: "오늘 급식",
    rows: ["현미밥", "미역국", "닭갈비", "콩나물무침", "우유"],
    action: "684.2 kcal",
    accent: "yellow",
  },
  {
    title: "반찬 선택",
    heading: "이 반찬을 안 먹을까요?",
    rows: ["콩나물무침", "오늘의 퀘스트", "한 입 도전!"],
    action: "한 입 도전",
    accent: "orange",
  },
  {
    title: "영양소 손실 안내",
    heading: "콩나물무침을 안 먹으면",
    rows: ["비타민", "식이섬유", "철분", "단백질"],
    action: "대체 음식 보기",
    accent: "mint",
  },
  {
    title: "레벨업 결과",
    heading: "한 입 도전 성공!",
    rows: ["EXP +20", "편식 몬스터에게 35 데미지", "초록쉴드 뱃지 획득"],
    action: "기록 저장",
    accent: "purple",
  },
  {
    title: "보호자 요약",
    heading: "보호자 요약",
    rows: ["이번 주 편식 경향", "한 입 도전 5회", "알레르기 선택값 확인"],
    action: "주간 리포트",
    accent: "blue",
  },
];

const levels: Level[] = [
  { level: "Lv.1", name: "냠냠 새싹", detail: "첫 급식 도전을 시작해요." },
  { level: "Lv.2", name: "한입 탐험가", detail: "새로운 반찬을 탐험해요." },
  { level: "Lv.3", name: "냠냠 용사", detail: "어려운 반찬도 한 입!" },
  { level: "Lv.4", name: "편식 몬스터 사냥꾼", detail: "도전 기록이 쌓여요." },
  { level: "Lv.5", name: "급식 히어로", detail: "꾸준한 습관이 보여요." },
  { level: "Lv.6", name: "영양 마스터", detail: "균형 잡힌 선택을 배워요." },
  { level: "Lv.7", name: "레전드 냠냠러", detail: "건강한 습관의 주인공!" },
];

const publicData = [
  {
    title: "NEIS 급식식단정보",
    lines: ["학교별 급식 메뉴", "칼로리", "영양정보", "알레르기 유발 식재료 번호"],
    icon: Utensils,
  },
  {
    title: "NEIS 학교기본정보",
    lines: ["학교 검색", "교육청 코드", "학교 코드"],
    icon: Search,
  },
  {
    title: "식품영양성분DB정보",
    lines: ["음식명 기반 영양소 추정 고도화 참고 데이터"],
    icon: Database,
  },
];

const privacyPrinciples = [
  "회원가입 없이 시작합니다.",
  "이름, 전화번호, 이메일을 받지 않습니다.",
  "별명과 학교 선택만 사용합니다.",
  "도전 기록은 기기 내부에 저장됩니다.",
  "서버 저장을 하지 않는 구조로 시작합니다.",
  "광고와 인앱결제가 없습니다.",
  "알레르기 정보는 선택 입력이며, 보호자와 학교 안내를 함께 확인해야 합니다.",
];

const faqs = [
  {
    question: "회원가입이 필요한가요?",
    answer: "아니요. 별명과 학교만 선택하면 바로 시작할 수 있도록 설계하고 있습니다.",
  },
  {
    question: "개인정보를 저장하나요?",
    answer: "이름, 전화번호, 이메일은 받지 않습니다. 도전 기록은 기기 내부 저장을 기본으로 합니다.",
  },
  {
    question: "영양소 안내는 정확한 진단인가요?",
    answer: "아니요. 의학 진단이 아니라 교육용 참고 정보입니다. 조리법과 배식량에 따라 달라질 수 있습니다.",
  },
  {
    question: "학교 급식 정보는 어디서 가져오나요?",
    answer: "NEIS 급식식단정보와 학교기본정보를 활용해 학교별 메뉴와 관련 정보를 안내합니다.",
  },
  {
    question: "무료인가요?",
    answer: "무료 출시를 목표로 개발 중이며, 광고와 인앱결제 없이 시작할 계획입니다.",
  },
];

function Header() {
  const [isOpen, setIsOpen] = useState(false);

  return (
    <header className="site-header">
      <a className="brand" href="#intro" aria-label="냠냠레벨업 홈">
        <img src="/assets/logo-reference.png" alt="" />
        <span>냠냠레벨업</span>
      </a>

      <button
        className="menu-button"
        type="button"
        aria-label={isOpen ? "메뉴 닫기" : "메뉴 열기"}
        aria-expanded={isOpen}
        onClick={() => setIsOpen((current) => !current)}
      >
        {isOpen ? <X size={22} /> : <Menu size={22} />}
      </button>

      <nav className={isOpen ? "nav-links is-open" : "nav-links"} aria-label="주요 메뉴">
        {navItems.map((item) => (
          <a key={item.id} href={`#${item.id}`} onClick={() => setIsOpen(false)}>
            {item.label}
          </a>
        ))}
      </nav>
    </header>
  );
}

function SectionTitle({
  id,
  eyebrow,
  title,
  description,
  icon,
}: {
  id?: string;
  eyebrow?: string;
  title: string;
  description?: string;
  icon?: ReactNode;
}) {
  return (
    <div className="section-title" id={id}>
      {eyebrow && <span className="section-eyebrow">{eyebrow}</span>}
      <h2>
        {icon}
        {title}
      </h2>
      {description && <p>{description}</p>}
    </div>
  );
}

function AppButton({
  icon,
  label,
  detail,
  disabled = false,
}: {
  icon: ReactNode;
  label: string;
  detail: string;
  disabled?: boolean;
}) {
  return (
    <button className="store-button" type="button" disabled={disabled}>
      {icon}
      <span>
        <small>{detail}</small>
        {label}
      </span>
    </button>
  );
}

function PhoneMockup({ size = "large", preview }: { size?: "large" | "small"; preview?: Preview }) {
  const rows = preview?.rows ?? ["현미밥", "미역국", "닭갈비", "콩나물무침", "배추김치", "우유"];
  const heading = preview?.heading ?? "오늘 급식";

  return (
    <div className={`phone-shell phone-${size}`} aria-label={`${heading} 앱 화면 예시`}>
      <div className="phone-notch" />
      <div className="phone-screen">
        <div className="phone-status">
          <span>9:41</span>
          <span>●●●</span>
        </div>
        <div className="phone-header">
          <span className="mini-leaf" aria-hidden="true">
            <Sparkles size={14} />
          </span>
          <strong>{heading}</strong>
          <span className="mini-leaf" aria-hidden="true">
            <Sparkles size={14} />
          </span>
        </div>
        <div className={`meal-card tone-${preview?.accent ?? "green"}`}>
          {rows.map((row) => (
            <span key={row}>{row}</span>
          ))}
        </div>
        <div className="nutrition-card">
          <strong>{preview?.action ?? "684.2 kcal"}</strong>
          <div>
            <span>탄수화물 91.2g</span>
            <span>단백질 28.4g</span>
            <span>지방 19.1g</span>
          </div>
        </div>
        <div className="phone-tabs">
          <span />
          <span />
          <span />
          <span />
        </div>
      </div>
    </div>
  );
}

function Hero() {
  return (
    <section className="hero-section" id="intro">
      <div className="hero-copy">
        <h1>
          <span>냠냠</span>레벨업
        </h1>
        <p className="hero-subtitle">한 입의 도전으로 레벨업!</p>
        <p className="hero-description">
          오늘 급식에서 안 먹는 반찬을 누르면, 놓칠 수 있는 영양소를 알려주고 한 입 도전으로 건강한
          식습관을 만들어가는 앱입니다.
        </p>
        <div className="hero-actions">
          <a className="primary-action" href="#launch">
            <Bell size={19} />
            출시 준비중
          </a>
          <a className="secondary-action" href="#features">
            앱 소개 보기
          </a>
        </div>
        <div className="trust-grid" aria-label="서비스 원칙">
          {trustCards.map((card) => (
            <div className="trust-card" key={card}>
              <Check size={18} />
              <span>{card}</span>
            </div>
          ))}
        </div>
      </div>

      <div className="hero-visual" aria-label="냠냠레벨업 앱 미리보기">
        <div className="mascot-card">
          <img src="/assets/mascot-thumb.png" alt="냠냠레벨업 캐릭터" />
        </div>
        <PhoneMockup />
      </div>
    </section>
  );
}

function FeatureCard({ feature }: { feature: Feature }) {
  const Icon = feature.icon;

  return (
    <article className="feature-card">
      <div className="feature-icon">
        <Icon size={34} strokeWidth={2.4} />
      </div>
      <h3>{feature.title}</h3>
      <p>{feature.description}</p>
    </article>
  );
}

function Features() {
  return (
    <section className="content-section" aria-labelledby="features">
      <SectionTitle
        id="features"
        title="주요 기능"
        description="학생은 쉽고 재미있게, 보호자는 안심하고 확인할 수 있는 급식 영양교육 흐름입니다."
        icon={<Sparkles size={30} />}
      />
      <div className="feature-grid">
        {features.map((feature) => (
          <FeatureCard key={feature.title} feature={feature} />
        ))}
      </div>
    </section>
  );
}

function PreviewSection() {
  return (
    <section className="content-section preview-section" aria-labelledby="preview">
      <SectionTitle
        id="preview"
        title="앱 화면 미리보기"
        description="실제 스크린샷이 준비되기 전까지 HTML/CSS 목업으로 사용자 흐름을 보여줍니다."
        icon={<Apple size={30} />}
      />
      <div className="preview-grid">
        {previews.map((preview) => (
          <article className="preview-card" key={preview.title}>
            <PhoneMockup size="small" preview={preview} />
            <h3>{preview.title}</h3>
          </article>
        ))}
      </div>
    </section>
  );
}

function LevelSection() {
  return (
    <section className="content-section level-section" aria-labelledby="levelup">
      <SectionTitle
        id="levelup"
        title="레벨업 & 캐릭터"
        description="도전할수록 레벨이 오르고 캐릭터가 조금씩 성장합니다."
        icon={<Star size={30} />}
      />
      <div className="level-visual">
        <img src="/assets/level-lineup.png" alt="Lv.1부터 Lv.7까지 성장하는 냠냠레벨업 캐릭터 라인업" />
      </div>
      <div className="level-grid">
        {levels.map((level) => (
          <article className="level-card" key={level.level}>
            <span>{level.level}</span>
            <h3>{level.name}</h3>
            <p>{level.detail}</p>
          </article>
        ))}
      </div>
    </section>
  );
}

function DataPrivacy() {
  return (
    <section className="split-band" aria-label="활용 데이터와 개인정보 보호">
      <div className="split-panel" id="data">
        <SectionTitle title="활용 공공데이터" icon={<Database size={30} />} />
        <div className="data-list">
          {publicData.map((item) => {
            const Icon = item.icon;
            return (
              <article className="data-item" key={item.title}>
                <div className="data-icon">
                  <Icon size={28} />
                </div>
                <div>
                  <h3>{item.title}</h3>
                  <ul>
                    {item.lines.map((line) => (
                      <li key={line}>{line}</li>
                    ))}
                  </ul>
                </div>
              </article>
            );
          })}
        </div>
        <p className="notice">
          영양소 안내는 의학 진단이 아니라 교육용 참고 정보입니다. 실제 영양소는 조리법과 배식량에
          따라 달라질 수 있습니다.
        </p>
      </div>

      <div className="split-panel privacy-panel" id="privacy">
        <SectionTitle title="개인정보 보호 원칙" icon={<LockKeyhole size={30} />} />
        <ul className="privacy-list">
          {privacyPrinciples.map((principle) => (
            <li key={principle}>
              <ShieldCheck size={20} />
              <span>{principle}</span>
            </li>
          ))}
        </ul>
        <img className="privacy-mascot" src="/assets/mascot-heart.png" alt="하트를 들고 있는 냠냠레벨업 캐릭터" />
      </div>
    </section>
  );
}

function LaunchSection() {
  return (
    <section className="launch-section" id="launch" aria-labelledby="launch-title">
      <div>
        <h2 id="launch-title">
          지금 바로 <span>냠냠레벨업</span>을 준비해보세요!
        </h2>
        <p>iPhone 앱 개발 중이며, TestFlight 준비 후 App Store 무료 출시를 목표로 합니다.</p>
      </div>
      <div className="launch-actions" aria-label="출시 안내 버튼">
        <AppButton icon={<Apple size={28} />} detail="App Store" label="출시 준비중" disabled />
        <AppButton icon={<Download size={28} />} detail="TestFlight" label="준비 예정" disabled />
        <a className="outline-link" href="#privacy">
          개인정보처리방침 보기
        </a>
        <a className="outline-link" href="mailto:support@naymnaym.example">
          <Mail size={18} />
          문의하기
        </a>
      </div>
      <p className="android-note">Android 버전은 현재 준비중이며, 이번 페이지는 iPhone 앱 출시 안내에 맞춰 구성했습니다.</p>
    </section>
  );
}

function FAQSection() {
  const [openIndex, setOpenIndex] = useState(0);

  return (
    <section className="content-section faq-section" aria-labelledby="faq">
      <SectionTitle id="faq" title="FAQ" description="학생과 보호자가 가장 먼저 궁금해할 내용을 짧게 정리했습니다." />
      <div className="faq-list">
        {faqs.map((faq, index) => {
          const isOpen = openIndex === index;
          return (
            <article className="faq-item" key={faq.question}>
              <button type="button" aria-expanded={isOpen} onClick={() => setOpenIndex(isOpen ? -1 : index)}>
                <span>{faq.question}</span>
                <ChevronDown className={isOpen ? "rotated" : ""} size={22} />
              </button>
              {isOpen && <p>{faq.answer}</p>}
            </article>
          );
        })}
      </div>
    </section>
  );
}

function Footer() {
  return (
    <footer className="site-footer">
      <div>
        <img src="/assets/logo-reference.png" alt="" />
        <strong>냠냠레벨업</strong>
      </div>
      <p>
        급식 영양교육 iPhone 앱 홍보 페이지. 문의:{" "}
        <a href="mailto:support@naymnaym.example">support@naymnaym.example</a>
      </p>
      <p className="footer-disclaimer">
        본 서비스의 영양소 안내는 교육용 참고 정보이며, 알레르기 정보는 보호자와 학교 안내를 함께 확인해야
        합니다.
      </p>
    </footer>
  );
}

export function App() {
  return (
    <>
      <Header />
      <main>
        <Hero />
        <Features />
        <PreviewSection />
        <LevelSection />
        <DataPrivacy />
        <LaunchSection />
        <FAQSection />
      </main>
      <Footer />
    </>
  );
}

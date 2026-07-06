// Firebase 설정
const firebaseConfig = {
  apiKey: "AIzaSyDsku8G3Uj_0ohATX1fTplToK7GlHwYxpI",
  authDomain: "mobit-68833.firebaseapp.com",
  databaseURL: "https://mobit-68833-default-rtdb.firebaseio.com",
  projectId: "mobit-68833",
  storageBucket: "mobit-68833.appspot.com",
  messagingSenderId: "270516790230",
  appId: "1:270516790230:web:bc62a8fd21536574f73a77"
};

let DEVICE_UUID = null;
let ADMIN_MODE = false;

// ✅ Swift에서 이 함수를 호출해 UUID를 설정하고 관리자 여부를 판단함
window.setDeviceUUID = function(uuid) {
  if (!uuid) {
    if (window.webkit?.messageHandlers?.MobitCommunity) {
      window.webkit.messageHandlers.MobitCommunity.postMessage({
        type: "log",
        content: "UUID is null or undefined."
      });
    }
    return;
  }

  DEVICE_UUID = uuid;
  checkIfAdmin(uuid);
};

// Firebase 초기화
firebase.initializeApp(firebaseConfig);
const database = firebase.database();

// 글 등록
function submitPost() {
  const content = getInputVal("postContent");
  if (!content) {
    if (window.webkit?.messageHandlers?.MobitCommunity) {
      window.webkit.messageHandlers.MobitCommunity.postMessage({
        type: "none",
        content: content
      });
    }
    return alert("내용을 입력하세요");
  }

  const postRef = database.ref("mobit_community").push(); // 고유 key 생성
  postRef
    .set({
      content: content,
      createdAt: Date.now()
    })
    .then(() => {
      document.getElementById("postContent").value = "";
      loadPosts();

      // iOS WebView로 메시지 전달
      if (window.webkit?.messageHandlers?.MobitCommunity) {
        window.webkit.messageHandlers.MobitCommunity.postMessage({
          type: "success",
          content: content
        });
      }
    })
    .catch((err) => {
      console.error("글 저장 실패:", err);
      if (window.webkit?.messageHandlers?.MobitCommunity) {
        window.webkit.messageHandlers.MobitCommunity.postMessage({
          type: "failure",
          content: content,
          error: err.message
        });
      }
    });
}

// 입력값 가져오기
function getInputVal(id) {
  return document.getElementById(id).value;
}

// 시간 포맷
function formatDate(timestamp) {
  const date = new Date(timestamp);
  return date.toLocaleString("ko-KR", { timeZone: "Asia/Seoul" });
}

// 글 목록 로딩
function loadPosts() {
  const dataRef = database.ref("mobit_community").orderByChild("createdAt");
  dataRef.off(); // 중복 리스너 방지
  dataRef.on("value", (snapshot) => {
    const data = snapshot.val();
    const postsContainer = document.getElementById("postsContainer");
    const countEl = document.getElementById("postsCount");
    const emptyEl = document.getElementById("postsEmpty");
    postsContainer.innerHTML = "";

    const sortedKeys = data
      ? Object.keys(data).sort((a, b) => data[b].createdAt - data[a].createdAt)
      : [];

    if (countEl) countEl.textContent = sortedKeys.length ? String(sortedKeys.length) : "";
    if (emptyEl) emptyEl.hidden = sortedKeys.length > 0;

    sortedKeys.forEach((key) => {
      const post = data[key];
      postsContainer.appendChild(createPostElement(key, post));
    });
  });
}

// 게시글 DOM 생성
function createPostElement(key, post) {
  const article = document.createElement("article");
  article.className = "post";

  // 작성자 헤더 (익명 아바타 + 이름 + 시간)
  const head = document.createElement("div");
  head.className = "post-head";

  const avatar = document.createElement("div");
  avatar.className = "avatar";
  avatar.textContent = "익";

  const meta = document.createElement("div");
  meta.className = "post-meta";

  const author = document.createElement("span");
  author.className = "post-author";
  author.textContent = "익명 사용자";

  const time = document.createElement("span");
  time.className = "post-date";
  time.textContent = formatDate(post.createdAt);

  meta.appendChild(author);
  meta.appendChild(time);
  head.appendChild(avatar);
  head.appendChild(meta);
  article.appendChild(head);

  // 본문
  const content = document.createElement("div");
  content.className = "post-content";
  content.textContent = post.content;
  article.appendChild(content);

  // 관리자 답변
  if (post.adminReply?.content) {
    article.appendChild(createReplyElement(post.adminReply));
  }

  // 관리자 모드일 경우 답변 작성 UI 노출
  if (ADMIN_MODE) {
    showAdminUI(key, article);
  }

  return article;
}

// 관리자 답변 DOM 생성 (좌측 색바 없이 배지 + 들여쓰기)
function createReplyElement(adminReply) {
  const reply = document.createElement("div");
  reply.className = "reply";

  const head = document.createElement("div");
  head.className = "reply-head";

  const badge = document.createElement("span");
  badge.className = "reply-badge";
  badge.textContent = "관리자";

  const time = document.createElement("span");
  time.className = "reply-date";
  time.textContent = formatDate(adminReply.createdAt);

  head.appendChild(badge);
  head.appendChild(time);

  const content = document.createElement("div");
  content.className = "reply-content";
  content.textContent = adminReply.content;

  reply.appendChild(head);
  reply.appendChild(content);
  return reply;
}

// ✅ 관리자 여부를 확인하고 UI를 조정
function checkIfAdmin(uuid) {
  console.log("🔍 checkIfAdmin called with uuid:", uuid);

  const adminRef = database.ref(`adminUuids/${uuid}`);
  adminRef.once("value")
  .then(snapshot => {
    if (snapshot.exists()) {
      ADMIN_MODE = true;
    } else {
      ADMIN_MODE = false;
    }
  })
  .catch(error => {
    if (window.webkit?.messageHandlers?.MobitCommunity) {
      window.webkit.messageHandlers.MobitCommunity.postMessage({
        type: "log",
        content: "🔥 Firebase read 실패:" + error
      });
    }
    console.error("🔥 Firebase read 실패:", error);
  });

  loadPosts();
}

function showAdminUI(postKey, container) {
  const replyForm = document.createElement("div");
  replyForm.className = "reply-form";

  const replyTextarea = document.createElement("textarea");
  replyTextarea.placeholder = "관리자 답변 작성...";
  replyTextarea.className = "reply-input";
  replyTextarea.rows = 2;

  const replyButton = document.createElement("button");
  replyButton.type = "button";
  replyButton.textContent = "답변 등록";
  replyButton.className = "reply-submit";

  replyButton.onclick = () => {
    const replyContent = replyTextarea.value.trim();
    if (!replyContent) return alert("답변 내용을 입력해주세요.");

    const updateRef = database.ref(`mobit_community/${postKey}/adminReply`);
    updateRef.set({
      content: replyContent,
      createdAt: Date.now()
    }).then(() => {
      loadPosts();
    });
  };

  replyForm.appendChild(replyTextarea);
  replyForm.appendChild(replyButton);
  container.appendChild(replyForm);
}

// 초기 실행
// loadPosts();

// submitPost를 window에 붙여서 버튼에서도 작동하게 함
window.submitPost = submitPost;

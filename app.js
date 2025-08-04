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

// 글 목록 로딩
function loadPosts() {
  const dataRef = database.ref("mobit_community").orderByChild("createdAt");
  dataRef.off(); // 중복 리스너 방지
  dataRef.on("value", (snapshot) => {
    const data = snapshot.val();
    const postsContainer = document.getElementById("postsContainer");
    postsContainer.innerHTML = "";

    if (!data) return;

    const sortedKeys = Object.keys(data).sort((a, b) => data[b].createdAt - data[a].createdAt);
    sortedKeys.forEach((key) => {
      const post = data[key];
      const div = document.createElement("div");
      div.className = "post-box";

      const contentDiv = document.createElement("div");
      contentDiv.className = "post-content";
      contentDiv.textContent = `💵 ${post.content}`;

      const timeDiv = document.createElement("div");
      timeDiv.className = "post-time";
      const date = new Date(post.createdAt);
      timeDiv.textContent = date.toLocaleString("ko-KR", { timeZone: "Asia/Seoul" });

      div.appendChild(contentDiv);
      div.appendChild(timeDiv);
      
      // ✅ 관리자 댓글 UI
      if (post.adminReply?.content) {
        const replyDiv = document.createElement("div");
        replyDiv.className = "admin-reply";
        
        const replyContentDiv = document.createElement("div");
        replyContentDiv.className = "admin-reply-content";
        replyContentDiv.textContent = `👨‍💻 관리자: ${post.adminReply.content}`;
        
        const replyTimeDiv = document.createElement("div");
        replyTimeDiv.className = "admin-reply-time";
        const replyDate = new Date(post.adminReply.createdAt);
        replyTimeDiv.textContent = replyDate.toLocaleString("ko-KR", { timeZone: "Asia/Seoul" });
        
        replyDiv.appendChild(replyContentDiv);
        replyDiv.appendChild(replyTimeDiv);
        div.appendChild(replyDiv);
      }
      
      // ✅ 관리자 모드일 경우 댓글 작성 UI 노출
      if (ADMIN_MODE) {
        showAdminUI(key, div);
      }
      
      postsContainer.appendChild(div);
    });
  });
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
  replyForm.className = "admin-reply-form";
  
  const replyTextarea = document.createElement("textarea");
  replyTextarea.placeholder = "관리자 댓글 작성...";
  replyTextarea.className = "admin-reply-input";
  replyTextarea.rows = 2;
  
  const replyButton = document.createElement("button");
  replyButton.textContent = "댓글 등록";
  replyButton.className = "admin-reply-button";
  
  replyButton.onclick = () => {
    const replyContent = replyTextarea.value.trim();
    if (!replyContent) return alert("댓글 내용을 입력해주세요.");

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

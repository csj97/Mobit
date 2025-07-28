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
      postsContainer.appendChild(div);
    });
  });
}

// 초기 실행
loadPosts();

// submitPost를 window에 붙여서 버튼에서도 작동하게 함
window.submitPost = submitPost;

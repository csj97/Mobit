// Firebase 설정
const firebaseConfig = {
  apiKey: "AIzaSyDsku8G3Uj_0ohATX1fTplToK7GlHwYxpI",
  authDomain: "mobit-68833.firebaseapp.com",
  databaseURL: "https://mobit-68833-default-rtdb.firebaseio.com",
  projectId: "mobit-68833",
  storageBucket: "mobit-68833.firebasestorage.app",
  messagingSenderId: "270516790230",
  appId: "1:270516790230:web:bc62a8fd21536574f73a77"
};

firebase.initializeApp(firebaseConfig);
const mobitRef = firebase.database().ref('mobit_community');

// 글 등록
function submitPost() {
  const content = document.getElementById("postContent").value.trim();
  if (!content) return alert("내용을 입력하세요");

  const postData = {
    content,
    createdAt: Date.now()
  };

  const newPostRef = mobitRef.push(); // 자동 key 생성
  newPostRef.set(postData)
    .then(() => {
      document.getElementById("postContent").value = "";
      loadPosts();

      // ✅ iOS 네이티브로 콜백 전송
      window.webkit?.messageHandlers?.MobitCommunity?.postMessage({
        type: "success",
        content: content
      });
    })
    .catch((err) => {
      console.error("글 저장 실패:", err);

      window.webkit?.messageHandlers?.MobitCommunity?.postMessage({
        type: "failure",
        content: content
      });
    });
}

// 글 목록 불러오기
function loadPosts() {
  mobitRef
    .orderByChild("createdAt")
    .once("value")
    .then((snapshot) => {
      const container = document.getElementById("postsContainer");
      container.innerHTML = "";

      const posts = [];
      snapshot.forEach((child) => {
        posts.push(child.val());
      });

      // 최신순 정렬 (timestamp 내림차순)
      posts.reverse().forEach((post) => {
        const div = document.createElement("div");
        div.className = "post";
        div.textContent = post.content;
        container.appendChild(div);
      });
    })
    .catch((err) => {
      console.error("글 로딩 실패:", err);
    });
}

// 초기 로딩
loadPosts();

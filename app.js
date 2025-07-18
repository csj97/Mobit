import { initializeApp } from "https://www.gstatic.com/firebasejs/10.12.0/firebase-app.js";
import { getDatabase, ref, set, push, onValue, orderByChild, serverTimestamp } from "https://www.gstatic.com/firebasejs/10.12.0/firebase-database.js";

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

const app = initializeApp(firebaseConfig);
const database = getDatabase(app);

// 글 등록
function submitPost() {
  var content = getInputVal('postContent');
  if (!content) return alert("내용을 입력하세요");
  
  const db = getDatabase();
  set(ref(db, 'mobit_community/'), {
    content: content,
    createdAt: serverTimestamp() 
  })
  .then(() => {
    document.getElementById("postContent").value = "";
    loadPosts();
    
    // ✅ iOS 네이티브로 성공 콜백 전송
    if (window.webkit?.messageHandlers?.MobitCommunity) {
      window.webkit.messageHandlers.MobitCommunity.postMessage({
        type: "success",
        content: content
      });
    }
  })
  .catch((err) => {
    console.error("글 저장 실패:", err);
    
    // ✅ iOS 네이티브로 실패 콜백 전송
    if (window.webkit?.messageHandlers?.MobitCommunity) {
      window.webkit.messageHandlers.MobitCommunity.postMessage({
        type: "failure",
        content: content,
        error: err.message
      });
    }
  });
}

function getInputVal(id) {
  return document.getElementById(id).value;
}

function loadPosts() {
  const db = getDatabase();
  const dataRef = ref(db, 'mobit_community/');
  onValue(dataRef, (snapshot) => {
    const data = snapshot.val();
    console.log(data); // { content: "...", createdAt: "..." }
  })
  .then(() => {

  })
  .catch((err) => {

  });
}

window.submitPost = submitPost;

// 초기 로딩
loadPosts();

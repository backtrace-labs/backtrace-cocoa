import Foundation
extension URLSession {

    typealias ResponseHandler = (Response) -> Void

    func async(_ urlRequest: URLRequest, handler: @escaping ResponseHandler) {
        let task = dataTask(with: urlRequest,
                            completionHandler: { (responseData, responseUrl, responseError) in
            let response = Response(responseData, responseUrl as? HTTPURLResponse, responseError)
            handler(response)
        })
        task.resume()
    }
}
